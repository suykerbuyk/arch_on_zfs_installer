#!/bin/sh

timedatectl set-ntp true
pacstrap /mnt base linux linux-firmware
genfstab -U /mnt >> /mnt/etc/fstab

