#!/bin/bash
set -e

DRIVES=""
BOOT_PARTS=""
SWAP_PARTS=""
ROOT_PARTS=""
for DSK in $(ls /dev/disk/by-id/wwn-0x5000* | grep -v part)
do
	echo "Wiping clean $DSK"
	wipefs -aq "${DSK}"
	echo "Partitioning $DSK"
	parted --script "${DSK}" \
		--align=optimal mklabel gpt \
		mkpart non-fs 0% 2 \
		mkpart primary 2 4096 \
		mkpart --align=optimal primary 4096 16384 \
		mkpart --align=optimal primary 16385 3800GB \
		set 1 bios_grub on set 2 boot on
	# Wake the kernel up to the changes on disk
	sleep 1
	partprobe
	#partx -a $DSK
	FINISHED=$(echo ${DSK} |awk -F '/' '{print $5}')
	DRIVES="$DRIVES $FINISHED"
	BOOT_PARTS="$BOOT_PARTS ${FINISHED}-part2"
	SWAP_PARTS="$SWAP_PARTS ${FINISHED}-part3"
	ROOT_PARTS="$ROOT_PARTS ${FINISHED}-part4"
done
echo "DRIVES: $DRIVES"
partprobe
sleep 5
partprobe
#echo "BOOT: $BOOT_PARTS"
#echo "SWAP: $SWAP_PARTS"
#echo "ROOT: $ROOT_PARTS"

# Get the kernel to take one more look.
partprobe

echo "Creating Root ZPOOL"
zpool create \
    -o ashift=12 \
    -O acltype=posixacl -O canmount=off -O compression=lz4 \
    -O dnodesize=auto -O normalization=formD -O relatime=on \
    -O xattr=sa -O mountpoint=/ -R /mnt \
    mgmt_rpool raidz2 ${ROOT_PARTS}

echo "Creating Boot ZPOOL"
zpool create -d\
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
    -O mountpoint=/boot -R /mnt/boot \
    mgmt_bpool raidz2  $BOOT_PARTS

zfs create -o canmount=off -o mountpoint=none mgmt_mgmt_rpool/ROOT
zfs create -o canmount=off -o mountpoint=none mgmt_bpool/BOOT
zfs create -o canmount=noauto -o mountpoint=/ mgmt_mgmt_rpool/ROOT/default
zfs create -o mountpoint=/boot mgmt_bpool/BOOT/default
zfs mount mgmt_mgmt_rpool/ROOT/default 
zfs mount mgmt_bpool/BOOT/default

zfs create                                 mgmt_mgmt_rpool/home
zfs create -o mountpoint=/root             mgmt_mgmt_rpool/home/root
zfs create -o canmount=off                 mgmt_mgmt_rpool/var
zfs create -o canmount=off                 mgmt_mgmt_rpool/var/lib
zfs create                                 mgmt_mgmt_rpool/var/log
zfs create                                 mgmt_mgmt_rpool/var/spool
zfs create -o com.sun:auto-snapshot=false  mgmt_mgmt_rpool/var/cache
zfs create -o com.sun:auto-snapshot=false  mgmt_mgmt_rpool/var/tmp
chmod 1777 /mnt/var/tmp
zfs create                                 mgmt_rpool/opt
zfs create                                 mgmt_rpool/opt/stx
zfs create                                 mgmt_rpool/srv
zfs create -o canmount=off                 mgmt_rpool/usr
zfs create                                 mgmt_rpool/usr/local
zfs create                                 mgmt_rpool/var/mail
zfs create                                 mgmt_rpool/var/snap
zfs create                                 mgmt_rpool/var/www
zfs create                                 mgmt_rpool/var/lib/AccountsService
zfs create -o com.sun:auto-snapshot=false  mgmt_rpool/var/lib/docker
zfs create -o com.sun:auto-snapshot=false  mgmt_rpool/var/lib/nfs
zfs create -o com.sun:auto-snapshot=false  mgmt_rpool/tmp
chmod 1777 /mnt/tmp
