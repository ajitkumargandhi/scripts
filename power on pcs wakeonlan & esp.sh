#!/bin/bash
ip_file="ipmacsrvlist.txt"
esp_list="esp_list.txt"
recipient="example@example.com"
subject="PC Status Report"
weakeup=""
status_report=""
status_down=""
datetime=`date`

while IFS=',' read -r f1 f2 f3
do
    sudo wakeonlan "$f2"
    if [ $? -eq 0 ]; then
    weakeup+="device $f1, $f3 at $f2 wake command sent\n"
    echo "device $f1, $f2 at $f3 wake command sent"
    fi
    sleep 2
done < $ip_file

while IFS=',' read -r e1 e2 
do
	curl http://"$e1"/poweron 
	sleep 10 
	echo "sleeping for 6 minuets. ping will start after 6 minute"
done < $esp_list
	sleep 6m

while IFS=',' read -r f1 f2 f3
do
    ping -c 1 "$f1" &> /dev/null
    if [ $? -eq 0 ]; then
        status_report+="device $f1, $f3 at $f2 is UP\n"
        # echo "device $f1, $f3 at $f2 is up"
    else
        sudo wakeonlan "$f2"
        sleep 5m
        ping -c 1 "$f1" &> /dev/null
        if [ $? -eq 0 ]; then
            status_report+="device $f1, $f3 at $f2 is UP\n"
        else
            status_down+="device $f1, $f3 at $f2 is DOWN\n"
            echo "device $f1, $f3 at $f2 is down"
        fi
    fi
done < $ip_file

if [ ! -z "${status_down}" ]; then
    # Send the status report via email
    #echo -e "$status_down" | mail -s "$subject" "$recipient"
    printf "To: user@example.com\nFrom: device@example.com\nSubject: Network device down\n\n$datetime\n\n$status_down" | /usr/sbin/ssmtp -t
fi
