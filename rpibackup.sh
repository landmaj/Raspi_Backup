#!/bin/bash
#
# This is a backup script for Raspberry Pi
# by Michal 'Landmaj' Wielunski
# It should work with any Raspbian derivative (but probably will not work with Noobs)
# Tested on DietPi v140 on Dec 29 2016
#
# ___CREDITS
#
# This script started as a modifcation of this: https://github.com/aweijnitz/pi_backup
# Almost whole backup section is taken from that script
#
# Resize function comes from: http://blog.osnz.co.nz/post/97106494057/shrinking-raspberry-pi-sd-card-images-for
#
# ___HOW TO USE
#
# Modify variables in the section below
# 
# Add <path_to_script>/rpibackup.sh {setup} to cron or run it by hand
# DO NOT run the script with {backup} or {cleanup} parameters as it can cause trouble
#
#___CHANGELOG
#
# 29-Dec-2016
# Created new script. Some of the code is copied from the old one, most of it is new.
# Too much changes to list
#
# 19-Jan-2017
# Removed pv requirement
#
# ___TO DO
#
# Sync time after reboot
#
# ======================== CHANGE THESE VALUES ========================

SUBFOLDER=
MOUNTPOINT=/mnt/backup
DIR=$MOUNTPOINT # This is where your backups will be stored. Change to $MOUNTPOINT/$SUBFOLDER if you want to keep backups from different host in separate folders
SCRIPT_LOCATION=$DIR # location of rpibackup.sh script
RETENTIONPERIOD=15 # how long to keep old backups
POSTPROCESS=1 # updates sytem

MAIL_NOTIFICATION=0 # requires installed and working ssmtp
RECIPIENT=recipient@example.com
SENDER=sender@example.com

# Add any services that might interfere during backup
# No need for start function since system reboots after backup
function stopServices {
	# Stop cron to prevent reboots from whatever you have there
	# Also prevents some errors from hourly cron tasks (fake-hwclock, etc)
	service cron stop
}


# ======================== FUNCTIONS ========================

function postProcessSucess {
	# Update Packages and Kernel
	echo -e "[$(date +"%a %H:%M")] Update Packages and Kernel" | tee -a $DIR/backup_$HOSTNAME.log
    sudo apt-get update
    sudo apt-get upgrade -y
    sudo apt-get autoclean

	echo -e "[$(date +"%a %H:%M")] Update Raspberry Pi Firmware" | tee -a $DIR/backup_$HOSTNAME.log
    sudo rpi-update
    sudo dietpi-update
    sudo ldconfig
}
# Function which tries to mount MOUNTPOINT
function mountMountPoint {
	# mount all drives in fstab (that means MOUNTPOINT needs an entry there)
	mount -a
}

# Function which resizes the final image
function resizeImage {

	echo -e "[$(date +"%a %H:%M")] Resizing image..." | tee -a $DIR/backup_$HOSTNAME.log
	IMG=$OFILE
	OSIZE=$(du -m $OFILE | cut -f1)
	
	P_START=$( fdisk -lu $IMG | grep Linux | awk '{print $2}' ) # Start of 2nd partition in 512 byte sectors
	P_SIZE=$(( $( fdisk -lu $IMG | grep Linux | awk '{print $3}' ) * 1024 )) # Partition size in bytes
	losetup /dev/loop2 $IMG -o $(($P_START * 512)) --sizelimit $P_SIZE
	fsck -fy /dev/loop2
	resize2fs -M /dev/loop2 # Make the filesystem as small as possible
	fsck -fy /dev/loop2
	P_NEWSIZE=$( dumpe2fs /dev/loop2 2>/dev/null | grep '^Block count:' | awk '{print $3}' ) # In 4k blocks
	P_NEWEND=$(( $P_START + ($P_NEWSIZE * 8) + 1 )) # in 512 byte sectors
	losetup -d /dev/loop2
	echo -e "p\nd\n2\nn\np\n2\n$P_START\n$P_NEWEND\np\nW\n" | fdisk $IMG
	I_SIZE=$((($P_NEWEND + 1) * 512)) # New image size in bytes
	truncate -s $I_SIZE $IMG
	
	FSIZE=$(du -m $OFILE | cut -f1)
	echo -e "[$(date +"%a %H:%M")] Finished resizing!" | tee -a $DIR/backup_$HOSTNAME.log
	echo -e "[$(date +"%a %H:%M")] Old size: $OSIZE MB " | tee -a $DIR/backup_$HOSTNAME.log
	echo -e "[$(date +"%a %H:%M")] New size: $FSIZE MB" | tee -a $DIR/backup_$HOSTNAME.log
}

# Function which sends email
function sendMail {

	PACKAGESTATUS=`dpkg -s ssmtp | grep Status`;
	if [[ $PACKAGESTATUS == S* ]]
  	then
		echo -e "[$(date +"%a %H:%M")] Sending last log as email to $RECIPIENT..."
		echo -e "To: $RECIPIENT" | tee -a $DIR/mail.txt
		echo -e "From: $SENDER" | tee -a $DIR/mail.txt
		echo -e "Subject: $BACKUP_STATUS $HOSTNAME backup on $DATE" | tee -a $DIR/mail.txt
		echo -e "" | tee -a $DIR/mail.txt
		grep -A100 "$DATE" $DIR/backup_$HOSTNAME.log | tee -a $DIR/mail.txt
		ssmtp $RECIPIENT < $DIR/mail.txt
		rm $DIR/mail.txt
  	else
		echo -e "[$(date +"%a %H:%M")] Package 'ssmtp' is NOT installed" | tee -a $DIR/backup_$HOSTNAME.log
		echo -e "[$(date +"%a %H:%M")] Email will not be sent" | tee -a $DIR/backup_$HOSTNAME.log
	fi
}

# This funtion removes any traces of the backup script from final image
function cleanupImage {
	
	echo -e "[$(date +"%a %H:%M")] Cleaning up final image file" | tee -a $DIR/backup_$HOSTNAME.log
	
	# Mount final image to a new directory in /mnt
	OFFSET=$(( $( fdisk -lu $OFILE | grep Linux | awk '{print $2}' ) * 512 ))
	IMG_DIR=/mnt/img_$(date +%Y%m%d_%H%M%S)
	mkdir $IMG_DIR
	mount -v -o offset=$OFFSET -t ext4 $OFILE $IMG_DIR
	
	# Restore fstab and remove init.d script
	rm $IMG_DIR/etc/fstab
	mv $IMG_DIR/etc/fstab.bak /$IMG_DIR/etc/fstab
	rm $IMG_DIR/etc/init.d/rpibackup
	find $IMG_DIR/etc/rc*.d/ -name *rpibackup -exec rm "{}" \;
	
	# Unmount img file and remove mountpoint
	umount $IMG_DIR
	rmdir $IMG_DIR
}


# ======================== SCRIPT ========================

# Check if script was started as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

# ======================== SETUP ========================
case "$1" in
	setup)
	
	# Check if mount point is mounted, if not quit!
	if ! mountpoint -q "$MOUNTPOINT" ; then
		echo -e "[$(date +"%a %H:%M")] Destination is not mounted; attempting to mount ... "
		mountMountPoint
		if ! mountpoint -q "$MOUNTPOINT" ; then
			echo -e "[$(date +"%a %H:%M")]  Unable to mount $MOUNTPOINT; Aborting! "
			exit 1
		fi
		echo -e "[$(date +"%a %H:%M")] Mounted $MOUNTPOINT; Continuing backup" | tee -a $DIR/backup_$HOSTNAME.log
	fi
	
	# Check if backup directory exists
	if [ ! -d "$DIR" ];
	  then
		 mkdir $DIR
		 echo -e "[$(date +"%a %H:%M")] Backup directory $DIR didn't exist, I created it" | tee -a $DIR/backup_$HOSTNAME.log
	fi
	
	# Stop cron
	stopServices
	
	# Create a new section in log file
	echo -e " " | tee -a $DIR/backup_$HOSTNAME.log
	echo -e "===============================================================" | tee -a $DIR/backup_$HOSTNAME.log

	# This variable is used to sed file before sending email
	DATE=$(date)
	echo -e "$DATE" | tee -a $DIR/backup_$HOSTNAME.log
	echo -e " " | tee -a $DIR/backup_$HOSTNAME.log
	echo -e "[$(date +"%a %H:%M")] Starting Raspberry Pi backup process!" | tee -a $DIR/backup_$HOSTNAME.log
	
	# Change file system to read only
	echo -e "[$(date +"%a %H:%M")] Changing file system to read only" | tee -a $DIR/backup_$HOSTNAME.log
	mv /etc/fstab /etc/fstab.bak
	awk '$2~"^/$"{$4="ro,"$4}1' OFS="\t" /etc/fstab.bak | awk '$2~"^/boot$"{$4="ro,"$4}1' OFS="\t" > /etc/fstab
	
	# Create init.d script
	echo -e "[$(date +"%a %H:%M")] Creating startup script" | tee -a $DIR/backup_$HOSTNAME.log
	#Change this line if you added/removed any lines from init.d section at the bottom
	tail -n 27 $SCRIPT_LOCATION/rpibackup.sh > /etc/init.d/rpibackup
	sed -i -- "s|PLACEHOLDER|$SCRIPT_LOCATION|g" /etc/init.d/rpibackup
	chmod +x /etc/init.d/rpibackup
	update-rc.d rpibackup defaults
	
	
	# Export $DATE to init.d scrit so it can be used after restart
	echo $DATE >> /etc/init.d/rpibackup
	
	# Reboot to apply changes
	echo -e "[$(date +"%a %H:%M")] Rebooting" | tee -a $DIR/backup_$HOSTNAME.log
	reboot
	
	;;

# ======================== BACKUP ========================
	backup)
		
	# Check if mount point is mounted, if not, cleanup and quit!
	if ! mountpoint -q "$MOUNTPOINT" ; then
		echo -e "[$(date +"%a %H:%M")] Destination is not mounted; attempting to mount ... "
		mountMountPoint
		if ! mountpoint -q "$MOUNTPOINT" ; then
			echo -e "[$(date +"%a %H:%M")]  Unable to mount $MOUNTPOINT; Aborting! "
			$SCRIPT_LOCATION/rpibackup.sh cleanup
			echo -e "[$(date +"%a %H:%M")] Rebooting" | tee -a $DIR/backup_$HOSTNAME.log
			reboot
		fi
		echo -e "[$(date +"%a %H:%M")] Mounted $MOUNTPOINT; Continuing backup" | tee -a $DIR/backup_$HOSTNAME.log
	fi
	
	# Check if pv package is installed, if not, install it first
	PACKAGESTATUS=`dpkg -s pv | grep Status`;

	if [[ $PACKAGESTATUS == S* ]]
	   then
		  echo -e "[$(date +"%a %H:%M")]  Package 'pv' is installed" | tee -a $DIR/backup_$HOSTNAME.log
	   else
		  echo -e "[$(date +"%a %H:%M")]  Package 'pv' is NOT installed" | tee -a $DIR/backup_$HOSTNAME.log
		  echo -e "[$(date +"%a %H:%M")]  Installing package 'pv' + 'pv dialog'. Please wait..." | tee -a $DIR/backup_$HOSTNAME.log
		  sudo apt-get -y install pv && sudo apt-get -y install pv dialog
	fi

	
	# Stop cron
	stopServices
	
	# Create a filename with datestamp for our current backup
	OFILE="$DIR/backup_$(hostname)_$(date +%Y%m%d_%H%M%S)".img
	
	# Import $DATE from init.d
	DATE=$(tail -n 1 /etc/init.d/rpibackup)
			
	# First sync disks
	sync; sync

	# Begin the backup process, should take about 25 minutes from 8GB SD card to NFS
	echo -e "[$(date +"%a %H:%M")] Backing up SD card to img file on $DIR" | tee -a $DIR/backup_$HOSTNAME.log
	SDSIZE=`sudo blockdev --getsize64 /dev/mmcblk0`;
	sudo dd if=/dev/mmcblk0 of=$OFILE bs=1M conv=sync,noerror iflag=fullblock

	# Wait for dd backup to complete and catch result
	BACKUP_SUCCESS=$?
			
	# If command has completed successfully, delete previous backups and exit
	if [ $BACKUP_SUCCESS = 0 ];
		then
			
			# Restore original fstab and remove startup script
			$SCRIPT_LOCATION/rpibackup.sh cleanup
			
			# Downsize the img file and remove files left by the backup script
			resizeImage
			cleanupImage
										
			echo -e "[$(date +"%a %H:%M")] Raspberry Pi backup process completed!" | tee -a $DIR/backup_$HOSTNAME.log
			echo -e "[$(date +"%a %H:%M")] FILE: $OFILE" | tee -a $DIR/backup_$HOSTNAME.log
			
			# Remove old backups
			echo -e "[$(date +"%a %H:%M")] Removing backups older than $RETENTIONPERIOD days" | tee -a $DIR/backup_$HOSTNAME.log
			sudo find $DIR -maxdepth 1 -name "backup_$(hostname)*.img" -mtime +$RETENTIONPERIOD -exec rm {} \;
			echo -e "[$(date +"%a %H:%M")] If any backups older than $RETENTIONPERIOD days were found, they were deleted" | tee -a $DIR/backup_$HOSTNAME.log
						
			if [ $POSTPROCESS = 1 ] ;
				then
					postProcessSucess
			fi
			
			BACKUP_STATUS='SUCCESSFUL'
			if [ $MAIL_NOTIFICATION = 1 ] ;
				then
					sendMail
			fi
			
			echo -e "[$(date +"%a %H:%M")] Rebooting!" | tee -a $DIR/backup_$HOSTNAME.log
			reboot
					
			
		
		else 
			# Else remove attempted backup file
			echo -e "[$(date +"%a %H:%M")] Backup failed!" | tee -a $DIR/backup_$HOSTNAME.log
			sudo rm -f $OFILE
			
			# Restore original fstab and remove startup script
			$SCRIPT_LOCATION/rpibackup.sh cleanup
			
			echo -e "[$(date +"%a %H:%M")] Last backups on HDD:" | tee -a $DIR/backup_$HOSTNAME.log
			sudo find $DIR -maxdepth 1 -name "backup_$(hostname)*.img" -exec ls {} \;
			
			BACKUP_STATUS='FAILED'
			if [ $MAIL_NOTIFICATION = 1 ] ;
				then
					sendMail
			fi
			
			echo -e "[$(date +"%a %H:%M")] Rebooting!" | tee -a $DIR/backup_$HOSTNAME.log
			
			reboot

	fi
	;;
	
# ======================== CLEANUP ========================	
	cleanup)


	# Remount file system as read/write
	echo -e "[$(date +"%a %H:%M")] Remounting file system in rw mode" | tee -a $DIR/backup_$HOSTNAME.log
	mount -o remount,rw /
	
	# Restore original fstab
	echo -e "[$(date +"%a %H:%M")] Restoring fstab" | tee -a $DIR/backup_$HOSTNAME.log
	if [ -e /etc/fstab.bak ] ;
		then
			rm /etc/fstab
			mv /etc/fstab.bak /etc/fstab
		else
			echo -e "[$(date +"%a %H:%M")] /etc/fstab.bak was not found, no changes were made" | tee -a $DIR/backup_$HOSTNAME.log
	fi
	
	#Remove init.d script
	echo -e "[$(date +"%a %H:%M")] Removing startup script" | tee -a $DIR/backup_$HOSTNAME.log
	rm /etc/init.d/rpibackup
	update-rc.d -f rpibackup remove
	
	exit 0	
	
	;;
	
	*)
	echo "Usage: <path to script>/rpibackup.sh setup"
	exit 1
	;;

esac
# =====================================================================

exit 1






# =================== INIT.D SECTION =============================
# ======== DO NOT ADD OR REMOVE ANY LINES BELOW THIS =============
# ========== OR YOUR STARTUP SCRIPT WILL BE FUCKED ===============
# ============ IF YOU HAVE TO CHANGE SOMETHING ===================
# === MODIFY THE NUMBER OF LINES TO COPY IN SETUP SCRIPT =========
#!/bin/bash
#
### BEGIN INIT INFO
# Provides:     rpibackup
# Required-Start:  $all
# Required-Stop:
# Default-Start:   2 3 4 5
# Default-Stop:   0 1 6
# Short-Description: Raspi Backup
# Description:    Starts Raspberry Pi backup process.
### END INIT INFO

case "$1" in
	start)
		sleep 5
		mount -a
		sleep 10
		PLACEHOLDER/rpibackup.sh backup
		;;
	stop)
		echo "stop was not defined."
		;;
	*)
		echo "Usage: /etc/init.d/rpibackup {start|stop}"
		;;
esac
exit 0
