#!/bin/sh

fgrep zfs /etc/pacman.conf
if [ $? == 1 ]; then
	echo "Adding Arch ZFS Repo"
	echo "[archzfs]" >>/etc/pacman.conf
	echo "Server = http://archzfs.com/\$repo/x86_64" >>/etc/pacman.conf
	echo "SigLevel = Optional TrustAll" >>/etc/pacman.conf
else
	echo "Arch ZFS Repo already present"
fi
timedatectl set-ntp true
sed -i '/#en_US.UTF-8 UTF-8/s/^#//g' /etc/locale.gen
echo "LANG=en_US.UTF-8" >/etc/locale.conf
ln -sf /usr/share/zoneinfo/America/Denver /etc/localtime
hwclock --systohc
locale-gen
pacman -S --noconfirm --needed - <packages.x86_64
echo "root:clandestine" | chpasswd
# Fix brain dead grub probe!!!
ln -s /dev/sda1 /dev/scsi-35000c500302dc857-part1 
ln -s /dev/sda2 /dev/scsi-35000c500302dc857-part2
ln -s /dev/sda3 /dev/scsi-35000c500302dc857-part3
ln -s /dev/sda4 /dev/scsi-35000c500302dc857-part4


