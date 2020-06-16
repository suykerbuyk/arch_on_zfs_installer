#!/bin/sh
set -e
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

run "timedatectl set-ntp true"
run "hwclock --systohc"

if ! mount -l | grep ramdisk > /dev/null; then
	run "mount -t tmpfs -o size=8G ramdisk /var/cache/pacman"
fi
msg "Running pacstrap"
set -o errexit
pacstrap -c /mnt <packages.x86_64
set +o errexit
fgrep archzfs /mnt/etc/pacman.conf
if [ $? == 1 ]; then
        msg "Adding Arch ZFS Repo"
	cat <<- EOF_ZFS_REPO >> /mnt/etc/pacman.conf
	[archzfs]
	Server = http://archzfs.com/\$repo/x86_64
	SigLevel = Optional TrustAll
	EOF_ZFS_REPO
else
	msg "Arch ZFS Repo already present"
fi
echo "mgmt" >/mnt/etc/hostname
genfstab -U /mnt >> /mnt/etc/fstab
rsync -ar /var/cache/pacman/ /mnt/var/cache/pacman/

sed -i '/#en_US.UTF-8 UTF-8/s/^#//g' /mnt/etc/locale.gen
echo "LANG=en_US.UTF-8" >/mnt/etc/locale.conf

cat <<- EOF_BOOTSTRAP_SCRIPT >/mnt/root/boot_strap.sh
	#!/bin/sh
	locale-gen
	echo "root:clandestine | chpasswd"
EOF_BOOTSTRAP_SCRIPT
chmod +x /mnt/root/boot_strap.sh
arch-chroot /mnt "/root/boot_strap.sh"
