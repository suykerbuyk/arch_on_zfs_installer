#!/bin/sh
set -e

DSK=/dev/disk/by-id/scsi-35000c500302dc857
SYS_BASE_NAME="mgmt"
MNT="/mnt"

# Helps with debugging.
GO_SLOW=0
DRY_RUN=0

# Simple message output
msg() {
        printf "$@\n"
        [[ $GO_SLOW == 1 ]] && sleep 1
        return 0
}
err() {
        printf "$@\n"
        [[ $GO_SLOW == 1 ]] && sleep 1
        exit 1
}

# Run a command but first tell the user what its going to do.
run() {
        printf " $@ \n"
        [[ 1 == $DRY_RUN ]] && return 0
        eval "$@"; ret=$?
        [[ $ret == 0 ]] && return 0
        printf " $@ - ERROR_CODE: $ret\n"
        exit $ret
}

step01_destroy_what_is() {
	msg "Destroying and clearing target disk"
	run "umount /mnt/boot/esp || true"
	run "zpool destroy -f bpool  || true"
	run "zpool destroy -f rpool  || true"
	run "zpool labelclear "${DSK}-part3" || true"
	run "zpool labelclear "${DSK}-part4" || true"
	run "rm -rf /mnt/* "
	run "sgdisk --zap-all $DSK"
}
step02_partition_via_parted() {
	parted --script ${DSK} --align=optimal mklabel gpt mkpart non-fs 0% 2 mkpart primary 2 4096  \
	       mkpart --align=optimal primary 4096 16384   mkpart --align=optimal primary 16385 3800GB  \
		set 1 bios_grub on set 2 boot on
	partprobe $DSK
}
step02_partition_via_sgdisk() {
	msg "Configuring via sgdisk"
	run "sgdisk -a1 -n1:24K:+1000K -t1:EF02 $DSK  #nonfs mbr"
	run "sgdisk     -n2:1M:+512M   -t2:EF00 $DSK  #EFI/Boot"
	run "sgdisk     -n3:0:+1G      -t3:BF01 $DSK  #BOOT Pool"
	run "sgdisk     -n4:0:0        -t4:BF00 $DSK  #ROOT Pool"
	run "sgdisk     -u3=R"
	run "sgdisk     -u4=R"
	while [[ $(ls /dev/disk/by-id/scsi-35000c500302dc857* | grep part | wc -l) != 4 ]]; do
		echo "Waiting for partitions to show up"
		sleep 1
	done
	run "mkfs.vfat \"${DSK}-part2\""
}
step03_create_boot_pool() {
	msg "Creating BOOT pool"
	zpool create -f \
    -o ashift=12 -d \
    -o feature@async_destroy=enabled \
    -o feature@bookmarks=enabled \
    -o feature@embedded_data=enabled \
    -o feature@empty_bpobj=enabled \
    -o feature@enabled_txg=enabled \
    -o feature@extensible_dataset=enabled \
    -o feature@filesystem_limits=enabled \
    -o feature@hole_birth=enabled \
    -o feature@large_blocks=enabled \
    -o feature@lz4_compress=enabled \
    -o feature@spacemap_histogram=enabled \
    -o feature@zpool_checkpoint=enabled \
    -O acltype=posixacl -O canmount=off -O compression=lz4 \
    -O devices=off -O normalization=formD -O relatime=on -O xattr=sa \
    -O mountpoint=/boot -R /mnt \
    bpool "${DSK}-part3"
}
step04_create_boot_pool() {
	msg "Creating ROOT pool"
	zpool create -f \
    -o ashift=12 \
    -O acltype=posixacl -O canmount=off -O compression=lz4 \
    -O dnodesize=auto -O normalization=formD -O relatime=on \
    -O xattr=sa -O mountpoint=/ -R /mnt \
    rpool ${DSK}-part4
}
step05_create_filesystems(){
	msg "Creating ZFS file system containers"
	run "zfs create -o canmount=off -o mountpoint=none rpool/ROOT"
	run "zfs create -o canmount=noauto -o mountpoint=/ rpool/ROOT/${SYS_BASE_NAME}"
	run "zfs mount rpool/ROOT/${SYS_BASE_NAME}"

	run "zfs create -o canmount=off -o mountpoint=none bpool/BOOT"
	run "zfs create -o mountpoint=/boot bpool/BOOT/${SYS_BASE_NAME}"
	# They seem to be automounting anway
	#run "zfs mount bpool/BOOT/${SYS_BASE_NAME}"

	run "zfs create                                 rpool/home"
	run "zfs create                                 rpool/etc"
	run "zfs create -o mountpoint=/root             rpool/home/root"
	msg "Create container for /var and /var/lib"
	run "zfs create -o canmount=off                 rpool/var"
	run "zfs create -o canmount=off                 rpool/var/lib"
	run "zfs create                                 rpool/var/log"
	run "zfs create                                 rpool/var/spool"
	msg "Skip snapshots for /var/cache and /var/temp"
	run "zfs create -o com.sun:auto-snapshot=false  rpool/var/cache"
	run "zfs create -o com.sun:auto-snapshot=false  rpool/var/tmp"
	run "chmod 1777 /mnt/var/tmp"
	run "zfs create                                 rpool/opt"
	run "zfs create                                 rpool/opt/stx"
	run "zfs create                                 rpool/srv"
	msg "Create contianer for /usr"
	run "zfs create -o canmount=off                 rpool/usr"
	run "zfs create                                 rpool/usr/local"
	run "zfs create                                 rpool/var/www"
	msg "Don't snapshot nfs lock dir"
	run "zfs create -o com.sun:auto-snapshot=false  rpool/var/lib/nfs"
	msg "Disable snapshots on /tmp"
	zfs create -o com.sun:auto-snapshot=false  rpool/tmp
	chmod 1777 /mnt/tmp
	mkdir /mnt/boot/esp
	run "mount \"${DSK}-part2\" /mnt/boot/esp"
}

step11_set_time() {
	msg "Setting up time"
	run "timedatectl set-ntp true"
	run "hwclock --systohc"
}
step12_create_pacman_cache() {
	if ! mount -l | grep ramdisk > /dev/null; then
		msg "Creating Package Cache"
		run "mount -t tmpfs -o size=8G ramdisk /var/cache/pacman"
	else
		msg "Reusing Package Cache"
	fi
}

step13_run_pacstrap() {
	msg "Running pacstrap"
	set -o errexit
	run "pacstrap -c ${MNT} - <packages.x86_64"
	set +o errexit
}
step14_configure_target() {
	msg "Configuring Target"
	fgrep archzfs ${MNT}/etc/pacman.conf
	if [ $? == 1 ]; then
		msg "  Adding Arch ZFS Repo"
		cat <<- EOF_ZFS_REPO >> ${MNT}/etc/pacman.conf
		[archzfs]
		Server = http://archzfs.com/\$repo/x86_64
		SigLevel = Optional TrustAll
		EOF_ZFS_REPO
	else
		msg "  Arch ZFS Repo already present"
	fi
	echo "mgmt" >${MNT}/etc/hostname
	genfstab -U ${MNT} >> ${MNT}/etc/fstab
	rsync -ar /var/cache/pacman/ ${MNT}/var/cache/pacman/

	msg "  Configuring ssh"
	rsync -ar ./etc-ssh/ ${MNT}/etc/ssh/
	chown -R root:root ${MNT}/etc/ssh/*
	chmod -R 0700 ${MNT}/etc/ssh/authorized_keys
	chmod 0744 ${MNT}/etc/ssh/sshd_config
	chmod 0744 ${MNT}/etc/ssh/ssh_config
	msg "  Configuring locale"
	sed -i '/#en_US.UTF-8 UTF-8/s/^#//g' ${MNT}/etc/locale.gen
	echo "LANG=en_US.UTF-8" >${MNT}/etc/locale.conf
	cat <<- EOF_BOOTSTRAP_SCRIPT >${MNT}/root/boot_strap.sh
		#!/bin/sh
		locale-gen
		echo "root:clandestine | chpasswd"
	EOF_BOOTSTRAP_SCRIPT
	chmod +x ${MNT}/root/boot_strap.sh
	arch-chroot ${MNT} "/root/boot_strap.sh"
}
step20_install_grub(){
	ZPOOL_VDEV_NAME_PATH=1 grub-mkconfig -o /boot/grub/grub.cfg
	ZPOOL_VDEV_NAME_PATH=1 grub-install --target=x86_64-efi --efi-directory=/boot/esp/ --bootloader-id=GRUB
	ZPOOL_VDEV_NAME_PATH=1 grub-mkconfig -o /boot/grub/grub.cfg

}

prep_disk() {
	step01_destroy_what_is
	#step02_partition_via_parted
	step02_partition_via_sgdisk
	step03_create_boot_pool
	step04_create_boot_pool
	step05_create_filesystems
}
prep_image() {
	step11_set_time
	step12_create_pacman_cache
	step13_run_pacstrap
	step14_configure_target
}
prep_boot_loader() {
	step20_install_grub
}
prep_disk
prep_image
#prep_boot_loader
