#!/bin/bash
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
