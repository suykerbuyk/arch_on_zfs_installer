#!/bin/sh
rsync -avr ./cache_pacman/ root@mgmt:/var/cache/pacman/
rsync -avr ./etc-ssh/ root@mgmt:etc-ssh/
rsync -avr "package*" root@mgmt:
rsync -avr "*sh"  root@mgmt:
