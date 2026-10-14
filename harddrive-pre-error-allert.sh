#!/bin/bash

# ==========================================
# CONFIGURATION
#  Decentralized Hard-Drive SMART Health Monitor & Alert System
# ==========================================
#  PURPOSE:
#    Monitors SMART attributes (CRC errors, pending sectors, reallocated
#    sectors) on all ZFS and OS/LVM drives across a chain of servers.
#    Sends a consolidated email alert when hardware degradation is detected.
#
#  ALERT CONDITIONS:
#    • CRC errors (ID 199) exceed per-drive baseline  → cable/connection issue
#    • Pending sectors (ID 197) > 0                   → media degradation
#    • Reallocated sectors (ID 5) > 0                 → media degradation
#
#  DESIGN:
#    • Runs on EVERY server in the chain, but only ONE server executes
#      at a time (staggered via SSH neighbor detection).
#    • If the upstream neighbor is offline, this server proceeds
#      immediately (failsafe) so monitoring never stops.
#    • CRC baselines absorb known bad-cable noise; only NEW increase alerts.
#
#  DEPENDENCIES:
#    smartmontools, zfsutils, lvm2, udevadm, ssh (key-based root), mail
#
#  SETUP:
#    1. Edit SERVER_CHAIN with all server IPs in physical order.
#    2. On each server, set MY_IP to that server's own address.
#    3. Set EMAIL_ADDRESS to the alert recipient.
#    4. Add per-drive CRC baselines if a cable is known-bad.
#    5. Schedule via cron (e.g., */15 * * * * /path/to/drive-error-alert.sh)
# ==========================================
EMAIL_ADDRESS="your-email@example.com" # <-- change with your mail id to send you mail if any error generated for any hard drive)
HOSTNAME=$(hostname)

# Define the network chain order (List ALL your servers here in order)
# Example: Server 1 -> Server 2 -> Server 3 -> server 4
SERVER_CHAIN=("192.168.0.2" "192.168.0.3" "192.168.0.4" "192.168.0.5") # <-- replace ips with your all server ips
MY_IP="192.168.0.4" # <-- CHANGE THIS on each server to match ITS OWN IP address

# Baselines for past historical cable errors
declare -A CRC_BASELINES
CRC_BASELINES["sdb"]=1770

ALERT_TRIGGERED=0
EMAIL_BODY=""
RAW_DRIVE_LIST=""

# ==========================================
# DE-CENTRALIZED FAILSAFE LOGIC
# ==========================================
# Find where this server sits in the chain
for i in "${!SERVER_CHAIN[@]}"; do
   if [[ "${SERVER_CHAIN[$i]}" == "$MY_IP" ]]; then
       MY_INDEX=$i
       break
   fi
done

# If we are not the first server, check our neighbor before running
if [ "$MY_INDEX" -gt 0 ]; then
    NEIGHBOR_IP="${SERVER_CHAIN[$((MY_INDEX-1))]}"
    
    # Check if neighbor is online and currently running the script
    # We look for the process name 'drive-error-allert.sh' on the neighbor
    NEIGHBOR_ACTIVE=$(ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no root@"$NEIGHBOR_IP" "pgrep -f drive-error-allert.sh" 2>/dev/null)
    
    # Failsafe Trigger: If neighbor is actively running, we sleep for 5 minutes 
    # to let them finish so we don't clash resources or spam emails.
    if [ -n "$NEIGHBOR_ACTIVE" ]; then
        echo "Neighbor ($NEIGHBOR_IP) is currently running. Staggering execution... Sleeping 5 minutes."
        sleep 300
    else
        echo "Neighbor ($NEIGHBOR_IP) is offline or idle. Proceeding immediately (Failsafe Mode)."
    fi
fi

# ==========================================
# 1. AUTOMATIC ZFS DRIVE DETECTION
# ==========================================
ZFS_DRIVES=$(zpool status 2>/dev/null | awk '/ONLINE/ {print $1}' | grep -E '^(ata-|sd|nvme|wwn-)' | sort -u)
for Z_DRIVE in $ZFS_DRIVES; do
    REAL_NAME=$(udevadm info --query=name --name="/dev/disk/by-id/$Z_DRIVE" 2>/dev/null || udevadm info --query=name --name="$Z_DRIVE" 2>/dev/null)
    if [ -n "$REAL_NAME" ] && [ -b "/dev/$REAL_NAME" ]; then
        RAW_DRIVE_LIST+="/dev/$REAL_NAME "
    fi
done

# ==========================================
# 2. AUTOMATIC OS / LVM DRIVE DETECTION
# ==========================================
OS_PARTITION=$(df / | awk 'NR==2 {print $1}')
if [[ "$OS_PARTITION" =~ /dev/mapper/ ]] || [[ "$OS_PARTITION" =~ /dev/dm- ]]; then
    OS_PV=$(pvdisplay -c 2>/dev/null | cut -d: -f1 | head -n 1 | tr -d '[:space:]')
    if [ -n "$OS_PV" ]; then OS_PARTITION=$OS_PV; fi
fi
if [ -b "$OS_PARTITION" ]; then
    OS_DISK=$(lsblk -no pkname "$OS_PARTITION" | head -n 1 | tr -d '[:space:]')
    if [ -n "$OS_DISK" ]; then
        RAW_DRIVE_LIST+="/dev/$OS_DISK "
    else
        OS_DISK_RAW=$(echo "$OS_PARTITION" | sed -E 's/[0-p]+[0-9]+$//')
        RAW_DRIVE_LIST+="$OS_DISK_RAW "
    fi
fi

FINAL_DRIVES=$(echo "$RAW_DRIVE_LIST" | tr ' ' '\n' | grep -v '^$' | sort -u | tr '\n' ' ')

# ==========================================
# MONITORING LOGIC
# ==========================================
for DRIVE in $FINAL_DRIVES; do
    SHORT_NAME=$(basename "$DRIVE")
    SMART_DATA=$(smartctl -A "$DRIVE" 2>/dev/null)
    if [ -z "$SMART_DATA" ]; then continue; fi

    CURRENT_CRC=$(echo "$SMART_DATA" | awk '$1=="199" {print $10}')
    PENDING_SECTORS=$(echo "$SMART_DATA" | awk '$1=="197" {print $10}')
    REALLOCATED_SECTORS=$(echo "$SMART_DATA" | awk '$1=="5" {print $10}')

    CURRENT_CRC=${CURRENT_CRC:-0}
    PENDING_SECTORS=${PENDING_SECTORS:-0}
    REALLOCATED_SECTORS=${REALLOCATED_SECTORS:-0}
    BASELINE_CRC=${CRC_BASELINES[$SHORT_NAME]:-0}

    DRIVE_ALERT=0
    DRIVE_REPORT=""

    if [ "$CURRENT_CRC" -gt "$BASELINE_CRC" ]; then
        DRIVE_ALERT=1
        DRIVE_REPORT+="- CRITICAL: SATA Cable/Connection error count increased to $CURRENT_CRC (Baseline: $BASELINE_CRC)\n"
    fi
    if [ "$PENDING_SECTORS" -gt 0 ]; then
        DRIVE_ALERT=1
        DRIVE_REPORT+="- WARNING: Physical drive degradation! $PENDING_SECTORS pending bad sectors detected.\n"
    fi
    if [ "$REALLOCATED_SECTORS" -gt 0 ]; then
        DRIVE_ALERT=1
        DRIVE_REPORT+="- WARNING: Physical drive degradation! $REALLOCATED_SECTORS reallocated bad sectors detected.\n"
    fi

    if [ "$DRIVE_ALERT" -eq 1 ]; then
        ALERT_TRIGGERED=1
        EMAIL_BODY+="=========================================\n"
        EMAIL_BODY+="DEVICE ALERT: $DRIVE ($SHORT_NAME)\n"
        EMAIL_BODY+="=========================================\n"
        EMAIL_BODY+="$DRIVE_REPORT\n\n"
    fi
done

# ==========================================
# SEND ALERT IF ISSUES DETECTED
# ==========================================
if [ "$ALERT_TRIGGERED" -eq 1 ]; then
    FULL_MESSAGE=$(cat <<EOF
CRITICAL SMART ALERT: Server Storage Infrastructure Issue

Server Hostname: $HOSTNAME
Date/Time: $(date)

The automated storage monitor has detected anomalies in active system drives (ZFS / OS / LVM). Details below:

$(echo -e "$EMAIL_BODY")
Recommendations:
1. For Cable/CRC errors: Power off the server and replace the SATA data cable.
2. For Pending/Reallocated sectors: Prepare to swap the drive out as the hardware media is physically failing.
EOF
)
    echo "$FULL_MESSAGE" | mail -s "CRITICAL: Hard Drive Infrastructure Alert on $HOSTNAME" "$EMAIL_ADDRESS"
    logger -p local0.crit "Storage Drive Monitor: Critical hardware issues detected on active system drives."
fi
