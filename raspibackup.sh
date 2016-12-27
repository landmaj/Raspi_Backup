#!/bin/bash

# ___ CREDITS
# This script started from
#   http://raspberrypi.stackexchange.com/questions/5427/can-a-raspberry-pi-be-used-to-create-a-backup-of-itself
# which in turn started from
#   http://www.raspberrypi.org/phpBB3/viewtopic.php?p=136912
#
# Users of this script can just modify the below marked values (stopService,startservice function and directory to
# store the backup
#
# 2013-Sept-04
# Merged in later comments from the original thread (the pv exists check modified) and added the backup.log
#
# 2013-Sept-05
# Remved tar compression, since it takes FOREVER to complete and I don't need it.
#
# 2014-Feb-12
# Merged in comments from http://www.raspberrypi.org/forum/viewtopic.php?f=63&t=12079&p=494488
# Moved interesting variables to top of script
# Added options around updates and gzips
#
# 2016-Dec-25
# Added option to resize backup image using Perl scipt from https://www.raspberrypi.org/forums/viewtopic.php?f=91&t=58069
# Changed backup.log to backup_$HOSTNAME.log
# The script now only removes old backups from the host on which it runs
#
# 2016-Dec-27
# Removed all colouring from log to make it easily readable outside of Linux
# Added timestamps to log
# Removed gzip option completly since image resizing is faster and you can restore backup to smaller sd card
# Added email notification (requires installed and configured ssmtp)
#
# Add an entry to crontab to run regurlarly.
# Example: Update /etc/crontab to run backup.sh as root every night at 3am
# 01 4    * * *   root    /home/pi/scripts/backup.sh
#
# Remember to expand filesystem after restoring baackup if you used image resizing!
#


# ======================== CHANGE THESE VALUES ========================
function stopServices {
	echo -e "[$(date +"%a %H:%M")]  Stopping services before backup" | tee -a $DIR/backup_$HOSTNAME.log
    sudo service cron stop
    sudo service ssh stop
    sudo service samba stop
}

function startServices {
	echo -e "[$(date +"%a %H:%M")]  Starting the stopped services" | tee -a $DIR/backup_$HOSTNAME.log
    sudo service samba start
    sudo service ssh start
    sudo service cron start
}


# Setting up directories
SUBDIR=
MOUNTPOINT=/mnt/backup
DIR=$MOUNTPOINT/$SUBDIR
RESIZE_LOCATION=$MOUNTPOINT
RETENTIONPERIOD=15 # days to keep old backups
POSTPROCESS=0 # 1 to use a postProcessSucess function after successfull backup
RESIZE=1 # whether to resize final image

MAIL_NOTIFICATION=0 # wheter to send log as email after completition (requires installed and configured ssmtp)
RECIPIENT=recipient@example.com # email to which notification will be sent
SENDER=sender@example.com

# Function which tries to mount MOUNTPOINT
function mountMountPoint {
    # mount all drives in fstab (that means MOUNTPOINT needs an entry there)
    mount -a
}


function postProcessSucess {
	# Update Packages and Kernel
	echo -e "[$(date +"%a %H:%M")]  Update Packages and Kernel" | tee -a $DIR/backup_$HOSTNAME.log
    sudo apt-get update
    sudo apt-get upgrade -y
    sudo apt-get autoclean

	echo -e "[$(date +"%a %H:%M")]  Update Raspberry Pi Firmware" | tee -a $DIR/backup_$HOSTNAME.log
    sudo rpi-update
    sudo dietpi-update
    sudo ldconfig

    # Reboot now
    echo -e "[$(date +"%a %H:%M")]  Reboot now ..." | tee -a $DIR/backup_$HOSTNAME.log
    sudo reboot
}


# =====================================================================

# Function which resizes the final image
function resizeImage {
	echo -e "[$(date +"%a %H:%M")]  Resizing image..." | tee -a $DIR/backup_$HOSTNAME.log
	sudo perl $RESIZE_LOCATION/resizeimage.pl $OFILE | tee -a $DIR/backup_$HOSTNAME.log
		FIRSTPASS=${PIPESTATUS[0]}
		if [ $FIRSTPASS = 1 ] ;
			then
				echo -e "  " | tee -a $DIR/backup_$HOSTNAME.log
				echo -e "[$(date +"%a %H:%M")]  Second attempt due to error (this is normal)..." | tee -a $DIR/backup_$HOSTNAME.log
				sudo perl $RESIZE_LOCATION/resizeimage.pl $OFILE | tee -a $DIR/backup_$HOSTNAME.log
				if [ $? = 0 ] ;
					then
						echo -e "  " | tee -a $DIR/backup_$HOSTNAME.log
						echo -e "[$(date +"%a %H:%M")]  Resizing completed!" | tee -a $DIR/backup_$HOSTNAME.log
					else
						echo -e "  " | tee -a $DIR/backup_$HOSTNAME.log
						echo -e "[$(date +"%a %H:%M")]  There was an error with resizing." | tee -a $DIR/backup_$HOSTNAME.log
				fi
			else
						echo -e "  " | tee -a $DIR/backup_$HOSTNAME.log
						echo -e "[$(date +"%a %H:%M")]  Resizing completed!" | tee -a $DIR/backup_$HOSTNAME.log
		fi
}

# Function which sends email
function sendMail {

	PACKAGESTATUS=`dpkg -s ssmtp | grep Status`;
	if [[ $PACKAGESTATUS == S* ]]
   	then
		echo -e "[$(date +"%a %H:%M")]  Sending last log as email to $RECIPIENT..."
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


# Check if mount point is mounted, if not quit!

if ! mountpoint -q "$MOUNTPOINT" ; then
    echo -e "[$(date +"%a %H:%M")]  Destination is not mounted; attempting to mount ... "
    mountMountPoint
    if ! mountpoint -q "$MOUNTPOINT" ; then
        echo -e "[$(date +"%a %H:%M")]   Unable to mount $MOUNTPOINT; Aborting! "
        exit 1
    fi
    echo -e "[$(date +"%a %H:%M")]  Mounted $MOUNTPOINT; Continuing backup"
fi


#LOGFILE="$DIR/backup_$(date +%Y%m%d_%H%M%S).log"

# Check if backup directory exists
if [ ! -d "$DIR" ];
   then
      mkdir $DIR
	  echo -e "[$(date +"%a %H:%M")]  Backup directory $DIR didn't exist, I created it"  | tee -a $DIR/backup_$HOSTNAME.log
fi

echo -e "  " | tee -a $DIR/backup_$HOSTNAME.log
echo -e "===============================================================" | tee -a $DIR/backup_$HOSTNAME.log

# This variable is used to sed file before sending email
DATE=$(date)
echo -e "$DATE" | tee -a $DIR/backup_$HOSTNAME.log
echo -e "  " | tee -a $DIR/backup_$HOSTNAME.log
echo -e "[$(date +"%a %H:%M")]  Starting Raspberry Pi backup process!" | tee -a $DIR/backup_$HOSTNAME.log

# First check if pv package is installed, if not, install it first
PACKAGESTATUS=`dpkg -s pv | grep Status`;

if [[ $PACKAGESTATUS == S* ]]
   then
      echo -e "[$(date +"%a %H:%M")]  Package 'pv' is installed" | tee -a $DIR/backup_$HOSTNAME.log
   else
      echo -e "[$(date +"%a %H:%M")]  Package 'pv' is NOT installed" | tee -a $DIR/backup_$HOSTNAME.log
      echo -e "[$(date +"%a %H:%M")]  Installing package 'pv' + 'pv dialog'. Please wait..." | tee -a $DIR/backup_$HOSTNAME.log
      sudo apt-get -y install pv && sudo apt-get -y install pv dialog
fi

# Check if perl is installed if resize is enabled
if [ $RESIZE = 1 ] ;
    then
	# Check if perl is installed
	PACKAGESTATUS=`dpkg -s perl | grep Status`;

	if [[ $PACKAGESTATUS == S* ]]
   	then
      	    echo -e "[$(date +"%a %H:%M")]  Package 'perl' is installed" | tee -a $DIR/backup_$HOSTNAME.log
   	else
      	    echo -e "[$(date +"%a %H:%M")]  Package 'perl' is NOT installed" | tee -a $DIR/backup_$HOSTNAME.log
      	    echo -e "[$(date +"%a %H:%M")]  Installing package 'perl' Please wait..." | tee -a $DIR/backup_$HOSTNAME.log
      	    sudo apt-get -y install perl
	fi
fi



# Create a filename with datestamp for our current backup
OFILE="$DIR/backup_$(hostname)_$(date +%Y%m%d_%H%M%S)".img


# First sync disks
sync; sync

# Shut down some services before starting backup process
stopServices

# Begin the backup process, should take about 25 minutes from 8GB SD card to NFS
echo -e "[$(date +"%a %H:%M")]  Backing up SD card to img file on $DIR" | tee -a $DIR/backup_$HOSTNAME.log
SDSIZE=`sudo blockdev --getsize64 /dev/mmcblk0`;
sudo pv -tpreb /dev/mmcblk0 -s $SDSIZE | dd of=$OFILE bs=1M conv=sync,noerror iflag=fullblock

# Wait for dd backup to complete and catch result
BACKUP_SUCCESS=$?

# Start services again that where shutdown before backup process
startServices

# If command has completed successfully, delete previous backups and exit
if [ $BACKUP_SUCCESS =  0 ];
	then
		BACKUP_STATUS='SUCCESSFUL'
		if [ $RESIZE = 1 ] ;
			then
				resizeImage
		fi
						
		echo -e "[$(date +"%a %H:%M")]  Raspberry Pi backup process completed!" | tee -a $DIR/backup_$HOSTNAME.log
		echo -e "[$(date +"%a %H:%M")]  FILE: $OFILE" | tee -a $DIR/backup_$HOSTNAME.log
		echo -e "[$(date +"%a %H:%M")]  Removing backups older than $RETENTIONPERIOD days" | tee -a $DIR/backup_$HOSTNAME.log
		sudo find $DIR -maxdepth 1 -name "backup_$(hostname)*.img" -mtime +$RETENTIONPERIOD -exec rm {} \;
		echo -e "[$(date +"%a %H:%M")]  If any backups older than $RETENTIONPERIOD days were found, they were deleted" | tee -a $DIR/backup_$HOSTNAME.log
		
		if [ $MAIL_NOTIFICATION = 1 ] ;
			then
				sendMail
		fi
				
		if [ $POSTPROCESS = 1 ] ;
			then
				postProcessSucess
		fi
		
		exit 0
	
	else 
		BACKUP_STATUS='FAILED'
		# Else remove attempted backup file
		echo -e "[$(date +"%a %H:%M")]  Backup failed!" | tee -a $DIR/backup_$HOSTNAME.log
		sudo rm -f $OFILE
		echo -e "[$(date +"%a %H:%M")]  Last backups on HDD:" | tee -a $DIR/backup_$HOSTNAME.log
		sudo find $DIR -maxdepth 1 -name "backup_$(hostname)*.img" -exec ls {} \;
		if [ $MAIL_NOTIFICATION = 1 ] ;
			then
				sendMail
		fi
		exit 1
fi
