# Backup script for Raspberry Pi
This script does an image backup of the Pi SD card using dd. This is a heavily modified version of this: https://github.com/aweijnitz/pi_backup I removed the option to gzip backup in favor of a second script (not mine, link in credits) which reduces img file to its minimum possible size. This method is faster and allows to restore backup to smaller sd card.

I also added email notification after successful (or failed) backup. It requires installed and configured ssmtp.

## Installation
- Clone this repo into the folder where you keep your housekeeping scripts.
- Modify the DIR variable to point to your destination
- (optional) Modify RESIZE_LOCATION variable to point to .resizeimage.pl script
- Update services stop and start sections to reflect your installated services
- Make executable. ```chmod +x raspibackup.sh```
- Update crontab to run it each week

___Example (based on my setup using DietPi and NAS)___

1. Create directory /mnt/backup and edit /etc/fstab to mount an NFS share to this location
2. Copy ```.raspibackup.sh``` and ```.resizeimage.pl``` to ```/mnt/backup``` and run ```chmod +x /mnt/backup/.raspibackup.sh```
3. Create ```/etc/cron.weekly/backup``` with following content:
```
#!/bin/bash
/mnt/backup/.raspibackup.sh
```
4. Make it executable - ```chmod +x /etc/cron.weekly/backup```
5. And see if it works ```bash /etc/cron.weekly/backup```


## CREDITS
Backup script:
   https://github.com/aweijnitz/pi_backup
   
Resize scripts:
  https://www.raspberrypi.org/forums/viewtopic.php?f=91&t=58069
