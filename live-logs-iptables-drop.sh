#!/bin/bash
# ============================================================================
#  apache-ip-blocker.sh
#  Real-Time Apache Log Monitor & Auto IP Blocker (Ban → Unban → Re-ban Loop)
# ============================================================================
#
#  HOW IT WORKS:
#  ─────────────────────────────────────────────────────────────────────────
#  1. Tails Apache access/error logs in real-time (handles log rotation).
#  2. Greps for HTTP error codes: 400, 401, 404, 444.
#  3. Extracts the source IP and validates it.
#  4. If not already blocked → adds iptables DROP rule (all traffic from IP).
#  5. Logs the event to /var/log/iptables/blocked_ips.log.
#  6. Schedules auto-unblock after BAN_TIME seconds (default: 3600 = 1 hr).
#  7. If attacker hits again after unblock → immediately re-blocked.
#     (No persistence by design — the ban/unban/re-ban loop is the shield.)
#
#  DEPENDENCIES:
#  ─────────────────────────────────────────────────────────────────────────
#  • iptables (installed by default on Ubuntu)
#  • atd daemon (for scheduled unblocking)
#  • Apache 2 log files must exist at the paths in LOG_FILE array
#
#  TO RUN AS A SYSTEMD SERVICE (one-time setup):
#  ─────────────────────────────────────────────────────────────────────────
#  Step 1: Ensure 'atd' is running
#      sudo systemctl enable --now atd
#
#  Step 2: Create the log directory
#      sudo mkdir -p /var/log/iptables
#
#  Step 3: Create the systemd unit file
#      sudo nano /etc/systemd/system/apache-ip-blocker.service
#
#      Paste this content:
#
#      [Unit]
#      Description=Apache Log IP Auto-Blocker
#      After=network.target apache2.service
#
#      [Service]
#      Type=simple
#      ExecStart=/path/to/your/script/live-logs-iptables-drop.sh
#      Restart=always
#      RestartSec=5
#
#      [Install]
#      WantedBy=multi-user.target
#
#  Step 4: Replace /path/to/your/script/ with the ACTUAL path
#      (e.g., /opt/scripts/live-logs-iptables-drop.sh)
#
#  Step 5: Enable and start the service
#      sudo systemctl daemon-reload
#      sudo systemctl enable --now apache-ip-blocker
#
#  Step 6: Verify it's running
#      sudo systemctl status apache-ip-blocker
#      tail -f /var/log/iptables/blocked_ips.log
#
#  NOTES:
#  ─────────────────────────────────────────────────────────────────────────
#  • No iptables persistence is configured (by design).
#  • On reboot, the systemd service auto-starts within seconds,
#    so the attacker is re-blocked on their very next probe.
#  • To change ban duration, edit BAN_TIME (in seconds) in this script.
#  • To add more trusted IPs to whitelist, add them after grep -v:
#      | grep -v "192.168.0.1" | grep -v "10.0.0.5" | ...
# ============================================================================

# Configuration
LOG_FILE=("/var/log/apache2/access.log"
"/var/log/apache2/error.log"
)
SEARCH_STRING='" (444|401|404|400) '
# Time in seconds for IP to be blocked (e.g., 1 hour = 3600)
BAN_TIME=3600
# Log file to track blocked IPs
BLOCKED_IPS_LOG="/var/log/iptables/blocked_ips.log"

# Check if script is running as root
if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root. Exiting."
  exit 1
fi

echo "Starting log monitor for '${LOG_FILE}'..."
echo "Blocking IPs that return a '${SEARCH_STRING}' error."
echo "Blocked IPs will be logged to '${BLOCKED_IPS_LOG}'."

# Use tail to follow the log file, pipe output to grep
# Use `--line-buffered` with `grep` to ensure output is not delayed
tail -Fn0 "${LOG_FILE}" | grep -E --line-buffered "${SEARCH_STRING}" | grep -v "192.168.0.1" | while read -r line; do

  # Extract the IP address from the beginning of the line using awk
  # This assumes the IP is the first column
  IP_TO_BLOCK=$(echo "${line}" | awk '{print $1}')

  # Check if the extracted IP is a valid IPv4 address
  if [[ "${IP_TO_BLOCK}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then

    # Check if the IP is already in the iptables chain
    # Adding a redundant rule can cause performance issues
    if ! iptables -C INPUT -s "${IP_TO_BLOCK}" -j DROP 2>/dev/null; then
      echo "[$(date)] Blocking IP: ${IP_TO_BLOCK}"
      
      # Add iptables rule to drop all packets from this IP address
      iptables -A INPUT -s "${IP_TO_BLOCK}" -j DROP
      
      # Log the blocked IP and the line that triggered the block
      echo "[$(date)] IP blocked: ${IP_TO_BLOCK}. Reason: Found '${SEARCH_STRING}' in log line: ${line}" >> "${BLOCKED_IPS_LOG}"

      # Schedule the IP to be unblocked later using `at`
      if command -v at &>/dev/null; then
        echo "iptables -D INPUT -s ${IP_TO_BLOCK} -j DROP" | at now + "${BAN_TIME}" seconds
        echo "[$(date)] IP ${IP_TO_BLOCK} is scheduled to be unblocked in ${BAN_TIME} seconds." >> "${BLOCKED_IPS_LOG}"
      else
        echo "[$(date)] 'at' command not found. IP ${IP_TO_BLOCK} will remain blocked permanently." >> "${BLOCKED_IPS_LOG}"
      fi
    else
     echo "[$(date)] IP ${IP_TO_BLOCK} is already blocked. No action taken."
    fi
   fi
done
