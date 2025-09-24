#!/bin/bash

# Configuration
LOG_FILE=("/var/log/apache2/access.log"
"/var/log/apache2/error.log"
)
SEARCH_STRING=" 444 0 | 401 401 | 404 404 | 400 400 "
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
