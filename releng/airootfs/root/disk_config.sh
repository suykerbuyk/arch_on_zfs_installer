#!/bin/bash
set -e
SGT_MACH2_WWN_PREFIX='wwn-0x6000c500a'
SGT_EVANS_WWN_PREFIX='wwn-0x5000c500a'
SGT_TATSU_WWN_PREFIX='wwn-0x5000c5009'
SGT_NYTRO_WWN_PREFIX='wwn-0x5000c5003'

TGT_DRV="${SGT_NYTRO_WWN_PREFIX}"
SYS_BASE_NAME="mgmt"

# Global vars for all functions
DRIVES=""
BOOT_PARTS=""
SWAP_PARTS=""
ROOT_PARTS=""
DRV_COUNT=0

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

#Creates the actual partitions to install Arch
# We want an GPT area, a boot zfs boot artition that grub can work with
# and a fulll featured root partition
function mk_partitions() {
	for DSK in $(ls /dev/disk/by-id/${TGT_DRV}* | grep -v part)
	do
		msg "Wiping clean $DSK"
		run "wipefs -aq ${DSK}"
		partprobe $DSK
		msg "Partitioning $DSK"
		parted --script ${DSK} \
			--align=optimal mklabel gpt \
			mkpart non-fs 0% 2  \
			mkpart primary 2 4096  \
			mkpart --align=optimal primary 4096 16384  \
			mkpart --align=optimal primary 16385 3800GB  \
			set 1 bios_grub on set 2 boot on
		# Wake the kernel up to the changes on disk
		partprobe $DSK
		FINISHED=$(echo ${DSK} |awk -F '/' '{print $5}')
		DRIVES="$DRIVES $FINISHED"
		export BOOT_PARTS="$BOOT_PARTS ${FINISHED}-part2"
		export SWAP_PARTS="$SWAP_PARTS ${FINISHED}-part3"
		export ROOT_PARTS="$ROOT_PARTS ${FINISHED}-part4"
		DRV_COUNT=$(expr $DRV_COUNT + 1 )
	done
	echo "DRIVES: $DRIVES"
	echo "DRV_COUNT: $DRV_COUNT"
}
function mk_swap_fs() {
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
		run "mkswap -L $SWP_LABEL /dev/disk/by-id/$SWP_TGT"
		echo "LABEL=$SWP_LABEL  none  swap defaults,pri=10,nofail  0  0">>etc_fstab
	done
	IFS="${IFS_SAVE}"
	run "ls /dev/disk/by-label/${SYS_BASE_NAME}_swp* | sort"

}
function mk_root_pool() {
   # Get the kernel to take one more look.
   msg "Creating Root ZPOOL"
   run "zpool create \
   -o ashift=12 \
   -O acltype=posixacl -O canmount=off -O compression=lz4 \
   -O dnodesize=auto -O normalization=formD -O relatime=on \
   -O xattr=sa -O mountpoint=/ -R /mnt \
    ${SYS_BASE_NAME}_rpool raidz2 ${ROOT_PARTS}"
}
function mk_boot_pool() {
msg "Creating Boot ZPOOL"
run "zpool create -d\
    -o ashift=12 \
    -o feature@allocation_classes=enabled \
    -o feature@async_destroy=enabled      \
    -o feature@bookmarks=enabled          \
    -o feature@embedded_data=enabled      \
    -o feature@empty_bpobj=enabled        \
    -o feature@enabled_txg=enabled        \
    -o feature@extensible_dataset=enabled \
    -o feature@filesystem_limits=enabled  \
    -o feature@hole_birth=enabled         \
    -o feature@large_blocks=enabled       \
    -o feature@lz4_compress=enabled       \
    -o feature@project_quota=enabled      \
    -o feature@resilver_defer=enabled     \
    -o feature@spacemap_histogram=enabled \
    -o feature@spacemap_v2=enabled        \
    -o feature@userobj_accounting=enabled \
    -o feature@zpool_checkpoint=enabled   \
    -O acltype=posixacl -O canmount=off -O compression=lz4 \
    -O devices=off -O normalization=formD -O relatime=on -O xattr=sa \
    -O mountpoint=/boot -R /mnt \
    ${SYS_BASE_NAME}_bpool raidz2  $BOOT_PARTS"
}

wait_for_devices() {
	# We have four partitions per target device
	TGT_CNT=$(($DRV_COUNT * 4 ))
	while [ 1 ]
	do
		DEV_CNT=$(ls /dev/disk/by-id/${TGT_DRV}* | grep part | wc -l)
		msg "Waiting for all partioned devices to appear"
		msg "  Have: $DEV_CNT Need: $TGT_CNT"
		if [[ $DEV_CNT == $TGT_CNT ]]
		then
			msg "   Got them!"
			return
		fi
		sleep 1
	done
}
function mk_zfs_file_systems() {
   msg "Making ZFS File systems"
   run "zfs create -o canmount=off -o mountpoint=none ${SYS_BASE_NAME}_rpool/ROOT"
   run "zfs create -o canmount=off -o mountpoint=none ${SYS_BASE_NAME}_bpool/BOOT"
   run "zfs create -o canmount=noauto -o mountpoint=/ ${SYS_BASE_NAME}_rpool/ROOT/default"
   run "zfs create -o mountpoint=/boot                ${SYS_BASE_NAME}_bpool/BOOT/default"
   msg "Mounting ROOT"
   #run "zfs mount ${SYS_BASE_NAME}_rpool/ROOT/default "
   run "echo "Mounting BOOT""
   #run "zfs mount ${SYS_BASE_NAME}_bpool/BOOT/default"
   run "zfs create                                 ${SYS_BASE_NAME}_rpool/home"
   run "zfs create -o mountpoint=/root             ${SYS_BASE_NAME}_rpool/home/root"
   run "zfs create -o canmount=off                 ${SYS_BASE_NAME}_rpool/var"
   run "zfs create -o canmount=off                 ${SYS_BASE_NAME}_rpool/var/lib"
   run "zfs create                                 ${SYS_BASE_NAME}_rpool/var/log"
   run "zfs create                                 ${SYS_BASE_NAME}_rpool/var/spool"
   run "zfs create -o com.sun:auto-snapshot=false  ${SYS_BASE_NAME}_rpool/var/cache"
   run "zfs create -o com.sun:auto-snapshot=false  ${SYS_BASE_NAME}_rpool/var/tmp"
   run "chmod 1777 /mnt/var/tmp"
   run "zfs create                                 ${SYS_BASE_NAME}_rpool/opt"
   run "zfs create                                 ${SYS_BASE_NAME}_rpool/opt/stx"
   run "zfs create                                 ${SYS_BASE_NAME}_rpool/srv"
   run "zfs create -o canmount=off                 ${SYS_BASE_NAME}_rpool/usr"
   run "zfs create                                 ${SYS_BASE_NAME}_rpool/usr/local"
   run "zfs create                                 ${SYS_BASE_NAME}_rpool/var/mail"
   run "zfs create                                 ${SYS_BASE_NAME}_rpool/var/snap"
   run "zfs create                                 ${SYS_BASE_NAME}_rpool/var/www"
   run "zfs create                                 ${SYS_BASE_NAME}_rpool/var/lib/AccountsService"
   run "zfs create -o com.sun:auto-snapshot=false  ${SYS_BASE_NAME}_rpool/var/lib/docker"
   run "zfs create -o com.sun:auto-snapshot=false  ${SYS_BASE_NAME}_rpool/var/lib/nfs"
   run "zfs create -o com.sun:auto-snapshot=false  ${SYS_BASE_NAME}_rpool/tmp"
   run "chmod 1777 /mnt/tmp"
}

mk_partitions
wait_for_devices
mk_swap_fs
mk_root_pool
mk_boot_pool
mk_zfs_file_systems
