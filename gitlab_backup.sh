echo "Free space available on external disks is"
df -lh /dev/sdc1 |awk '{print $4}'
echo "Please adjest space available on /dev/sdc1 meanwhile through anothere terminal"
usbdisksize=$(df -lh /dev/sdc1 |awk '/G/ {print $4}' |sed -r  's/^[^0-9]*([0-9]+).*/\1/')
echo "starting gitlab Backup"
gitlab-backup create
echo "size and name of gitlab back file located at /var/opt/gitlab/backups/ is as under"
#ls \-lh /var/opt/gitlab/backups/$file |awk '{print $9 }'
file=$(ls /var/opt/gitlab/backups/ |grep "$(date +'%Y_%m_%d')")
filesize=$(du -h /var/opt/gitlab/backups/$file |awk '{print $1}' | sed -r  's/^[^0-9]*([0-9]+).*/\1/')
echo $file
echo $filesize
echo $usbdisk
#if $usbdisk < $filesize; then echo $filesize; else echo $usbdisk; fi
echo "Enter filename with path to backup"
read $file
echo "Free space available on external disks is"
df -lh /dev/sdc1 |awk '/G/ {print $4}'
#df -lh /dev/sdc1 |awk '{print $4}'
echo "Backup file size is"
ls \-lh /var/opt/gitlab/backups/$file |awk '{print $5}'
read -p "Are you sure to continue? (y/n) " RESP
if [ "$RESP" = "y" ]; then
echo "Copying backup to onedrive of User's account"
rclone copy /var/opt/gitlab/backups/$file onedrive1:Backup/ --progress
echo "moving file to external drive"
mv /var/opt/gitlab/backups/$file /media/gitlab_backups/ 
echo "taking backup of gitlab.rb and gitlab-secrets.json files to external drive"
rclone copy /etc/gitlab/gitlab* onedrive1:Backup/ --progress
cp /etc/gitlab/gitlab* /media/gitlab_backups/
#:end
else
echo  "Terminating script because you selected No"
#pause
fi
