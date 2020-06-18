#!/bin/sh
set -e
# Define top level disk identifiers
SGT_MACH2_WWN_PREFIX='wwn-0x6000c500a'
SGT_EVANS_WWN_PREFIX='wwn-0x5000c500a'
SGT_TATSU_WWN_PREFIX='wwn-0x5000c5009'
SGT_NYTRO_WWN_PREFIX='wwn-0x5000c5003'
# Pick the template we are after
TGT_DRV="${SGT_NYTRO_WWN_PREFIX}"

# Only used for single disk testing.
#DSK=/dev/disk/by-id/scsi-35000c500302dc857

# The name that makes this node unique
SYS_BASE_NAME="mgmt"

# Our common mount point for imaging operations.
MNT="/mnt"
# Name of the EFI System Partition mount point
ESP="EFI"

# Names of boot and root pools
BOOT_POOL="${SYS_BASE_NAME}_bpool"
ROOT_POOL="${SYS_BASE_NAME}_rpool"

# Partition numbers of various file systems/pools
EFI_PART="-part1"
SWAP_PART="-part2"
BOOT_PART="-part3"
ROOT_PART="-part4"
PART_COUNT=4




# Helps with debugging.
GO_SLOW=0
DRY_RUN=0


# Global vars for partion functions
DRIVES=""
BOOT_PARTS=""
SWAP_PARTS=""
ROOT_PARTS=""
DRV_COUNT=0


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

wait_for_partitions_to_appear() {
	# We have four partitions per target device
	TGT_CNT=$(($DRV_COUNT * $PART_COUNT ))
	while [ 1 ]
	do
		PART_CNT=$(ls /dev/disk/by-id/${TGT_DRV}* | grep part | wc -l)
		msg "Waiting for all partions to appear"
		msg "  Have: $PART_CNT Need: $TGT_CNT"
		if [[ $PART_CNT == $TGT_CNT ]]
		then
			msg "   Got them!"
			return
		fi
		sleep 1
	done
}
wait_for_partitions_to_disappear() {
	# We have four partitions per target device
	TGT_CNT=$(($DRV_COUNT * $PART_COUNT ))
	while [ 1 ]
	do
		PART_CNT=$(ls /dev/disk/by-id/${TGT_DRV}* | grep part | wc -l)
		msg "Waiting for all partions to disappear"
		msg "  Have: $PART_CNT Need: $TGT_CNT"
		if [[ $PART_CNT == 0 ]]
		then
			msg "   Partitions are gone!"
			return
		fi
		sleep 1
	done
}
step01_destroy_what_is() {
	msg "Destroying and clearing target disk"
	run "swapoff -a"
	if [[ ! $(mountpoint  ${MNT}/${ESP} >/dev/null) ]]; then
		run "umount ${MNT}/${ESP} || true"
	fi
	run "zpool destroy -f ${BOOT_POOL}  || true"
	run "zpool destroy -f ${ROOT_POOL}  || true"
	msg "  Clearing partitions"
	for PART in $(ls /dev/disk/by-id/${TGT_DRV}* | grep part)
	do
		msg "Wiping clean $PART"
		run "zpool labelclear -f ${PART} || true"
		run "wipefs -afq ${PART} || true"
	done
	msg "  Clearing disk"
	for DRV in $(ls /dev/disk/by-id/${TGT_DRV}* | grep -v part)
	do
		run "wipefs -afq ${DRV}"
		run "sgdisk --zap-all $DRV"
		partprobe ${DRV}
	done
	wait_for_partitions_to_disappear
}
step02_partition_via_parted() {
	DRV_COUNT=0
	for DEV in $(ls /dev/disk/by-id/${TGT_DRV}* | grep -v part)
	do
		msg "Partitioning $DEV"
		parted --script ${DEV} \
			--align=optimal mklabel gpt \
			mkpart non-fs 0% 2  \
			mkpart primary 2 4096  \
			mkpart --align=optimal primary 4096 16384  \
			mkpart --align=optimal primary 16385 3800GB  \
			set 1 bios_grub on set 2 boot on
		# Wake the kernel up to the changes on disk
		partprobe $DEV
		FINISHED=$(echo ${DEV} |awk -F '/' '{print $5}')
		DRIVES="$DRIVES $FINISHED"
		export BOOT_PARTS="$BOOT_PARTS /dev/disk/by-id/${FINISHED}${SWAP_PART}"
		export SWAP_PARTS="$SWAP_PARTS /dev/disk/by-id/${FINISHED}${BOOT_PART}"
		export ROOT_PARTS="$ROOT_PARTS /dev/disk/by-id/${FINISHED}${ROOT_PART}"
		DRV_COUNT=$(expr $DRV_COUNT + 1 )
	done
	echo "DRIVES: $DRIVES"
	echo "DRV_COUNT: $DRV_COUNT"
	wait_for_partitions_to_appear
}
step03_create_root_pool() {
	msg "Creating ROOT pool"
	run "zpool create -f \
    -o ashift=12 \
    -O acltype=posixacl -O canmount=off -O compression=lz4 \
    -O dnodesize=auto -O normalization=formD -O relatime=on \
    -O xattr=sa -O mountpoint=/ -R /mnt \
    ${ROOT_POOL} ${ROOT_PARTS}"
}
step04_create_boot_pool() {
	msg "Creating BOOT pool"
	#ZPOOL_IMPORT_PATH=/dev/disk/by-id/ zpool create -f \
	run "zpool create -f \
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
    ${BOOT_POOL} ${BOOT_PARTS}"
}
step05_create_swap() {
	msg "Making swap devices"
	truncate -s 0 etc_fstab
	IFS_SAVE="${IFS}"
	IFS=' '
	read -a STRARR <<< "$SWAP_PARTS"
	for (( n=0; n < ${#STRARR[*]}; n++))
	do
		SWP_TGT="${STRARR[n]}"
		SWP_LABEL="${SYS_BASE_NAME}_swp${n}"
		msg "Make $SWP_LABEL on $SWP_TGT"
		run "mkswap -L $SWP_LABEL $SWP_TGT"
		echo "LABEL=$SWP_LABEL  none  swap defaults,pri=10,nofail  0  0">>etc_fstab
	done
	IFS="${IFS_SAVE}"
	TGT_CNT=$(( $DRV_COUNT ))
	while [ 1 ]
	do
		PART_CNT=$(ls /dev/disk/by-id/${TGT_DRV}*${SWAP_PART} | wc -l)
		msg "Waiting for all $TGT_CNT swap partions to appear"
		msg "  Have: $PART_CNT Swap partitions. Need: $TGT_CNT"
		if [[ $PART_CNT == $TGT_CNT ]]
		then
			msg "   Got them!"
			return
		fi
		sleep 1
	done
	msg "Swap fstab entries cached in local file 'etc_fstab'"
	cat etc_fstab
}
step06_create_filesystems(){
	msg "Creating ZFS file system containers"
	run "zfs create -o canmount=off -o mountpoint=none ${ROOT_POOL}/ROOT"
	run "zfs create -o canmount=noauto -o mountpoint=/ ${ROOT_POOL}/ROOT/${SYS_BASE_NAME}"
	run "zfs mount ${ROOT_POOL}/ROOT/${SYS_BASE_NAME}"

	run "zfs create -o canmount=off -o mountpoint=none ${BOOT_POOL}/BOOT"
	run "zfs create -o mountpoint=/boot ${BOOT_POOL}/BOOT/${SYS_BASE_NAME}"
	# They seem to be automounting anway
	#run "zfs mount bpool/BOOT/${SYS_BASE_NAME}"

	run "zfs create                                 ${ROOT_POOL}/home"
	run "zfs create                                 ${ROOT_POOL}/etc"
	run "zfs create -o mountpoint=/root             ${ROOT_POOL}/home/root"
	msg "Create container for /var and /var/lib"
	run "zfs create -o canmount=off                 ${ROOT_POOL}/var"
	run "zfs create -o canmount=off                 ${ROOT_POOL}/var/lib"
	run "zfs create                                 ${ROOT_POOL}/var/log"
	run "zfs create                                 ${ROOT_POOL}/var/spool"
	msg "Skip snapshots for /var/cache and /var/temp"
	run "zfs create -o com.sun:auto-snapshot=false  ${ROOT_POOL}/var/cache"
	run "zfs create -o com.sun:auto-snapshot=false  ${ROOT_POOL}/var/tmp"
	run "chmod 1777 /mnt/var/tmp"
	run "zfs create                                 ${ROOT_POOL}/opt"
	run "zfs create                                 ${ROOT_POOL}/opt/stx"
	run "zfs create                                 ${ROOT_POOL}/srv"
	msg "Create contianer for /usr"
	run "zfs create -o canmount=off                 ${ROOT_POOL}/usr"
	run "zfs create                                 ${ROOT_POOL}/usr/local"
	run "zfs create                                 ${ROOT_POOL}/var/www"
	msg "Don't snapshot nfs lock dir"
	run "zfs create -o com.sun:auto-snapshot=false  ${ROOT_POOL}/var/lib/nfs"
	msg "Disable snapshots on /tmp"
	zfs create -o com.sun:auto-snapshot=false  ${ROOT_POOL}/tmp
	chmod 1777 /mnt/tmp
	mkdir ${MNT}/${ESP}
	FIRST_EFI_PART=$(ls /dev/disk/by-id/${TGT_DRV}*${EFI_PART} | head -1)
	msg "Formatting all EFI partitions"
	for PART in $(ls /dev/disk/by-id/${TGT_DRV}*${EFI_PART})
	do
		run "mkfs.vfat ${PART}"
	done
	msg "Mounting first EFI partition"
	run "mount ${FIRST_EFI_PART} ${MNT}/${ESP}"
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
	SCRIPT="/root/boot_strap.sh"
	cat <<- EOF_BOOTSTRAP_SCRIPT >${MNT}/${SCRIPT}
		#!/bin/sh
		locale-gen
		echo "root:clandestine | chpasswd"
	EOF_BOOTSTRAP_SCRIPT
	chmod +x ${MNT}/${SCRIPT}
	arch-chroot ${MNT} "${SCRIPT}"
	rm -f ${MNT}/${SCRIPT}
}
step20_install_grub(){
	SCRIPT="/root/grub_config.sh"
	cat <<- EOF_GRUB_CONFIG >${MNT}/${SCRIPT}
	#!/bin/sh
	ZPOOL_VDEV_NAME_PATH=1 grub-mkconfig -o /boot/grub/grub.cfg
	ZPOOL_VDEV_NAME_PATH=1 grub-install --target=x86_64-efi --efi-directory=/boot/esp/ --bootloader-id=GRUB
	ZPOOL_VDEV_NAME_PATH=1 grub-mkconfig -o /boot/grub/grub.cfg
	EOF_GRUB_CONFIG
	chmod +x ${MNT}/${SCRIPT}
	arch-chroot ${MNT} "${SCRIPT}"
	rm -f ${MNT}/${SCRIPT}
}

prep_disk() {
	step01_destroy_what_is
	step02_partition_via_parted
	step03_create_root_pool
	step04_create_boot_pool
	step05_create_swap
	step06_create_filesystems
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
