#!/bin/sh

# cat etc-ssh/ssh_config >/etc/ssh/ssh_config
# cat etc-ssh/sshd_config >/etc/ssh/sshd_config
# cp -aR etc-ssh/authorized_keys /etc/ssh/
# chmod -R 0700 /etc/ssh/authorized_keys
# chown -R root:root /etc/ssh/authorized_keys
# systemctl restart sshd
if ! mount -l | grep pacman_cache  > /dev/null; then
	mount -t tmpfs -o size=8G  pacman_cache /var/cache/pacman
fi
rm -f /root/install.txt
# echo "root:seagate" | chpasswd
