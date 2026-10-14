#!/bin/bash
# ============================================================================
#  network-device-monitor.sh
#  Network Device Ping Monitor & Down-Alert via Email
# ============================================================================
#
#  WHAT IT DOES:
#  ─────────────────────────────────────────────────────────────────────────
#  1. Reads a CSV file (devices.txt) containing:
#       IP,Location,DeviceName
#     Example row: 192.168.1.10,Server Room,Core Switch
#
#  2. Pings each device (2 packets, 1s interval between devices).
#
#  3. If ANY device is DOWN → sends an email alert listing:
#       • Timestamp
#       • All down devices (IP, location, name)
#
#  4. If all devices are UP → no email (silent).
#
#  PREREQUISITES:
#  ─────────────────────────────────────────────────────────────────────────
#  1. ssmtp must be installed and configured:
#       sudo apt install ssmtp
#       sudo nano /etc/ssmtp/ssmtp.conf
#       (Set: MailHub, AuthUser, AuthPass, FromLineOverride)
#
#  2. Create devices.txt in the same directory (or use absolute path):
#       192.168.1.1,Server Room,Core Switch
#       192.168.1.2,Server Room,Firewall
#       192.168.1.5,Warehouse,Camera-01
#
#  3. Ensure 'ping' is available (iputils-ping):
#       sudo apt install iputils-ping
#
#  HOW TO RUN:
#  ─────────────────────────────────────────────────────────────────────────
#  Manual:
#       sudo ./network-device-monitor.sh
#
#  Scheduled (e.g., every 5 minutes via cron):
#       crontab -e
#       */5 * * * * /path/to/network-device-monitor.sh
#
#  NOTES:
#  ─────────────────────────────────────────────────────────────────────────
#  • Only sends email when a device is DOWN (no "all clear" emails).
#  • To change ping count, edit -c 2 (higher = more reliable, slower).
#  • To add a whitelist of ignored devices, add a grep -v line before
#    the while loop (similar to the apache-ip-blocker script).
#
# ============================================================================   

#grep -v "^#" devices.txt | grep -v "^$" | while read output
ip_file="devices.txt"

# Email settings
recipient="test@example.com"
subject="PC Status Report"
status_report=""
status_down=""
datetime=`date`

while IFS=',' read -r f1 f2 f3
do
    ping -c 2 "$f1" &> /dev/null
    if [ $? -eq 0 ]; then
    status_report+="device $f1, $f3 at $f2 is UP\n"
#    echo "device $f1, $f3 at $f2 is up"
    sleep 1
    else
    status_down+="device $f1, $f3 at $f2 is DOWN\n"
#    echo "device $f1, $f3 at $f2 is down"
    fi
done < $ip_file

if [ ! -z "${status_down}" ]; then
    # Send the status report via email
    #echo -e "$status_down" | mail -s "$subject" "$recipient"
    printf "To: user@example.com\nFrom: pc@example.com\nSubject: Network device down\n\n$datetime\n\n$status_down" | /usr/sbin/ssmtp -t
 fi
