#!/bin/sh
#rsync -avr ~/cache_pacman/ root@mgmt:/var/cache/pacman/
rm /home/johns/.ssh/hosts/mgmt.host
rsync -avr ./etc-ss* \
	config_live.sh \
	customize_airootfs.sh \
	install_arch.sh  \
	zap_disk_config.sh \
	packages.x86_64 \
	root@mgmt:
ssh root@mgmt /root/config_live.sh
rsync -avr ~/cache_pacman/ root@mgmt:/var/cache/pacman/
