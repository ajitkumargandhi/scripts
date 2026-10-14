#!/bin/bash
# ============================================================================
#  gitlab-backup-to-onedrive.sh
#  GitLab Backup → OneDrive + External USB Drive
# ============================================================================
#
#  WHAT IT DOES:
#  ─────────────────────────────────────────────────────────────────────────
#  1. Checks free space on external USB disk (/dev/sdc1).
#  2. Creates a GitLab backup (gitlab-backup create).
#  3. Shows the generated backup file name and size.
#  4. Asks user to confirm which file to back up.
#  5. After confirmation:
#       a. Uploads backup to OneDrive via rclone (onedrive1:Backup/).
#       b. Moves backup file to external drive (/media/gitlab_backups/).
#       c. Copies gitlab.rb + gitlab-secrets.json to both destinations.
#
#  PREREQUISITES (one-time setup):
#  ─────────────────────────────────────────────────────────────────────────
#  1. Install rclone:
#       curl https://rclone.org/install.sh | sudo bash
#
#  2. Configure OneDrive remote (run once):
#       rclone config
#       → Choose "n" (New remote)
#       → Name it: onedrive
#       → Type: onedrive
#       → Follow OAuth flow (open browser, authorize)
#       → Test with: rclone lsd onedrive1:
#
#  3. Ensure external USB disk is mounted at /media/gitlab_backups:
#       sudo mkdir -p /media/gitlab_backups
#       sudo mount /dev/your-drive-partation /media/gitlab_backups
#       (Add to /etc/fstab for auto-mount on boot if needed)
#
#  4. Ensure gitlab-backup is available:
#       sudo gitlab-backup create   (test manually once)
#
#  HOW TO RUN:
#  ─────────────────────────────────────────────────────────────────────────
#  sudo ./gitlab-backup.sh
#
#  FOR SCHEDULED BACKUPS (cron, e.g., daily at 2 AM):
#  ─────────────────────────────────────────────────────────────────────────
#  crontab -e
#  0 2 * * * /path/to/gitlab-backup.sh >> /var/log/gitlab-backup.log 2>&1
#
#  NOTE: For cron, remove the interactive 'read' prompts or set
#        them to auto-accept (e.g., replace 'read' with echo "y" |).
#
# ============================================================================
# rclone configuration steps https://rclone.org/onedrive/
externaldrive=/dev/sdc1 # <-- change your drive partation here insted of /dev/sdc1

echo "Free space available on external disks is"
df -lh $externaldrive |awk '{print $4}' 

echo "Please adjest space available on /dev/sdc1 meanwhile through anothere terminal"
usbdisksize=$(df -lh $externaldrive |awk '/G/ {print $4}' |sed -r  's/^[^0-9]*([0-9]+).*/\1/')

echo "starting gitlab Backup"
gitlab-backup create

echo "size and name of gitlab back file located at /var/opt/gitlab/backups/ is as under"
#ls -lh /var/opt/gitlab/backups/$file |awk '{print $9 }'
file=$(ls /var/opt/gitlab/backups/ |grep "$(date +'%Y_%m_%d')")
filesize=$(du -h /var/opt/gitlab/backups/$file |awk '{print $1}' | sed -r  's/^[^0-9]*([0-9]+).*/\1/')
echo $file
echo $filesize
echo $usbdisksize

#if $usbdisksize < $filesize; then echo $filesize; else echo $usbdisksize; fi

echo "Enter filename with path to backup"
read $file
echo "Free space available on external disks is"
df -lh $externaldrive |awk '/G/ {print $4}'
#df -lh $externaldrive |awk '{print $4}'
echo "Backup file size is"
ls \-lh /var/opt/gitlab/backups/$file |awk '{print $5}'
read -p "Are you sure to continue? (y/n) " RESP
if [ "$RESP" = "y" ]; then

echo "Copying backup to onedrive of User's account"
rclone copy /var/opt/gitlab/backups/$file onedrive:Backup/ --progress # <-- replace onedrive:Backup/ with your cloud storage path wherever you want to copy file
rclone copy /etc/gitlab/gitlab* onedrive:Backup/ --progress # <-- replace onedrive:Backup/ with your cloud storage path wherever you want to copy file

echo "moving file to external drive"
mv /var/opt/gitlab/backups/$file /media/gitlab_backups/ # <-- replace /media/gitlab_backups/ wherever you want to move file
echo "taking backup of gitlab.rb and gitlab-secrets.json files to external drive"
cp /etc/gitlab/gitlab* /media/gitlab_backups/ # <-- replace /media/gitlab_backups/ wherever you want to copy file
#:end
else
echo  "Terminating script because you selected No"
#pause
fi
