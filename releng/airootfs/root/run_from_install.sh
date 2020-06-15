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
