#!/bin/sh
rsync -avr root@mgmt:/var/cache/pacman/ ./cache_pacman/
rsync -avr root@mgmt:etc-ssh/ ./etc-ssh/
rsync -avr "root@mgmt:package*" .
rsync -avr "root@mgmt:*.sh" .
