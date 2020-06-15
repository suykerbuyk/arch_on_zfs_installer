#!/bin/sh
#mount -t tmpfs -o size=8G ramdisk /var/cache/pacman
timedatectl set-ntp true
pacstrap -c /mnt base base-devel linux linux-firmware vim archzfs-linux
genfstab -U /mnt >> /mnt/etc/fstab
cp packages.x86_64 /mnt/root/
rsync -ar /var/cache/pacman/ /mnt/var/cache/pacman/
cp ./run_from_install.sh /mnt/root/
