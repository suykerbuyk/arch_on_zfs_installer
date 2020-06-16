#!/bin/bash

#nonfs bootstrap partition: EF02
# EFI BOOT partion EF00

set -e
#DSK=/dev/sda
DSK=/dev/disk/by-id/scsi-35000c500302dc857
partprobe $DSK

SYS_BASE_NAME="mgmt"


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

use_parted(){
parted --script ${DSK} --align=optimal mklabel gpt mkpart non-fs 0% 2 mkpart primary 2 4096  \
       mkpart --align=optimal primary 4096 16384   mkpart --align=optimal primary 16385 3800GB  \
	set 1 bios_grub on set 2 boot on
partprobe $DSK
}
use_sgdisk(){
	run "umount /mnt/boot/esp || true"
	run "zpool destroy -f bpool  || true"
	run "zpool destroy -f rpool  || true"
	run "zpool labelclear "${DSK}-part3" || true"
	run "zpool labelclear "${DSK}-part4" || true"
	run "rm -rf /mnt/* "

	run "sgdisk --zap-all $DSK"
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

zpool create -f \
    -o ashift=12 \
    -O acltype=posixacl -O canmount=off -O compression=lz4 \
    -O dnodesize=auto -O normalization=formD -O relatime=on \
    -O xattr=sa -O mountpoint=/ -R /mnt \
    rpool ${DSK}-part4


	msg "Creating file system containers"
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
use_sgdisk
		
