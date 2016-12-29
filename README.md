 # Backup script for Raspbian and DietPi (and any similar distros for Raspberry Pi)
 
 This script will change your file system to read only, reboot and make backup of entire SD card.
 After the backup is done it will resize it to the smallest posible and remove any changes
 made to the system by the scipt.
 
 Remember to expand file system after restoring backup!

 ## Instalation

 - Copy this script to your backup location or directory with housekeeping scripts.
 - Make it executable ```chmod +x <path_to_script>/rpibackup.sh
 - Modify DIR variable to point to your backup folder
 - Modify SCRIPT_LOCATION variable to point to the script
 - Add it to cron or run it by hand using bash ```<path_to_script>/rpibackup.sh setup```
 
 ## Important notes
 
 This script modifies /etc/fstab so it is important that the file is properly formatted. 
 It will only work with basic partition setup (no system on USB drive, probably doesn't work with Noobs, etc).
 To make sure everything will work as intended run ```cat /etc/fstab```. Look for those two lines:
 
	```/dev/mmcblk0p1  /boot           auto    defaults,noatime,discard	0 2
	/dev/mmcblk0p2  /               auto    defaults,noatime,discard	0 1```

 If there are any 'ro' or 'rw', remove them using text editor.
 Next execute ```awk '$2~"^/$"{$4="ro,"$4}1' OFS="\t" /etc/fstab | awk '$2~"^/boot$"{$4="ro,"$4}1' OFS="\t" > /etc/fstab.copy```
 This will create a copy of your fstab. Print it: ```cat /etc/fstab.copy```
 You should see this:
 
 	```/dev/mmcblk0p1  /boot           auto    ro,defaults,noatime,discard	0 2
	/dev/mmcblk0p2  /               auto    ro,defaults,noatime,discard	0 1```
	
 If this is the case, the scipt will work fine. If not, don't risk.
 Remove the copy  ```rm /etc/fstab.copy```
 
 ## Email notification
 
 This requires installed and configured ssmtp. I highly recommend using it because after first reboot
 the script will become silent. You can see what it is doing in log but the script can send you this log
 after it finishes.
 
 ## Credits
 
 This script started as a modifcation of this: 
 https://github.com/aweijnitz/pi_backup

 Resize function comes from: 
 http://blog.osnz.co.nz/post/97106494057/shrinking-raspberry-pi-sd-card-images-for