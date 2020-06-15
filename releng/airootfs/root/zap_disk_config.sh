swapoff -a
zpool destroy mgmt_bpool ; zpool destroy mgmt_rpool ; rm -rf /mnt/boot /mnt/root  /mnt/usr  /mnt/var /mnt/dev  /mnt/etc  /mnt/proc  /mnt/run  /mnt/sys 
