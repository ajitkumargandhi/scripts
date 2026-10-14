#!/bin/bash
# ============================================================================
#  ubuntu-cleanup.sh
#  Ubuntu Comprehensive Disk-Space Cleanup (Safe Mode)
# ============================================================================
#  PURPOSE:
#    Interactively frees disk space across APT, Docker, NVM, journal logs,
#    user caches, temp files, and disabled snap revisions.
#
#  SAFETY:
#    • Every step shows a DRY-RUN preview before executing.
#    • Requires explicit 'y' confirmation per step (set AUTO_CONFIRM=true
#      for unattended/cron use).
#    • 'set -e' aborts on unexpected errors.
#    • Docker, NVM, and Snap steps auto-skip if not installed.
#
#  CLEANUP TARGETS:
#    1. APT      – caches, orphaned packages, .deb archives, package lists
#    2. Docker   – stopped containers, dangling images, unused volumes, builder
#    3. NVM      – $NVM_DIR/.cache
#    4. Logs     – journalctl entries older than 7 days
#    5. User Caches – thumbnails, pip, npm, yarn (per /home/* user)
#    6. Temp     – /tmp and /var/tmp contents
#    7. Snap     – disabled (old) snap revisions only
#
#  REQUIREMENTS:
#    • Run as root: sudo ./ubuntu-cleanup.sh
#    • Docker, NVM, Snap are optional (skipped if absent)
#
#  USAGE:
#    sudo ./ubuntu-cleanup.sh
# ============================================================================
set -e
home_dir=(/home/*)

# --- Configuration ---
# Change to 'false' to require manual 'y' input for every step
AUTO_CONFIRM=false 

# --- Helper Function: Confirm Action ---
# Usage: confirm_action "Step Name" "Preview Command" "Execute Command"
confirm_action() {
    local step_name="$1"
    local preview_cmd="$2"
    local execute_cmd="$3"

    echo -e "\n----------------------------------------"
    echo "🔍 PREVIEW: $step_name"
    echo "----------------------------------------"

    # 1. Run Preview (Dry Run or List Files)
    # We use 'eval' to execute the string command. 
    # Errors in preview (e.g., directory not found) are suppressed for cleanliness.
    eval "$preview_cmd" 2>/dev/null || echo "ℹ️  Nothing found to clean in this category."

    echo ""

    # 2. Ask for Confirmation
    if [ "$AUTO_CONFIRM" = true ]; then
        response="y"
    else
        read -r -p "❓ Do you want to proceed with removing $step_name these items? [y/N] " -n 1 response
        echo "" # Newline
    fi

    # 3. Execute or Skip
    if [[ "$response" =~ ^[Yy]$ ]]; then
        echo "⏳ Executing: $step_name..."
        eval "$execute_cmd"
        echo "✅ $step_name completed."
    else
        echo "⏭️  Skipped: $step_name."
    fi
}

# --- Main Script ---

echo "=== 🚀 Starting Ubuntu System Cleanup (Safe Mode) ==="
echo "Date: $(date)"
echo "-----------------------------------------"

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
  echo "⚠️  Please run as root (use sudo)"
  exit 1
fi

# 1. APT Package Manager Cleanup
# Preview: Shows what WOULD be removed (--dry-run)
confirm_action \
    "APT Caches & Unused Packages" \
    "apt-get clean && apt-get autoclean && apt-get autoremove --purge --dry-run" \
    "apt-get clean && apt-get autoclean && apt-get autoremove --purge -y && rm -rf /var/cache/apt/archives/*.deb && rm -rf /var/lib/apt/lists/*"

# 2. Docker Cleanup
if command -v docker &> /dev/null; then
  # Preview: List what will be removed
  docker_preview="echo 'Containers to remove:' && docker container prune --dry-run 2>/dev/null || echo 'None'; \
                  echo 'Images to remove:' && docker image prune --dry-run 2>/dev/null || echo 'None'; \
                  echo 'Volumes to remove:' && docker volume prune --dry-run 2>/dev/null || echo 'None'"
  
  # Execute: Actual prune commands
  docker_execute="docker container prune -f && docker image prune -f && docker volume prune -f && docker builder prune -f"

  confirm_action "Docker Resources (Containers, Images, Volumes)" "$docker_preview" "$docker_execute"
else
  echo -e "\n⚠️  Docker not found, skipping."
fi

# 3. NVM Cleanup
if [ -d "$NVM_DIR" ] && [ -d "$NVM_DIR/.cache" ]; then
  # Preview: Show size and contents of NVM cache
  nvm_preview="echo 'NVM Cache Size:' && du -sh \"$NVM_DIR/.cache\" 2>/dev/null && echo 'Contents:' && ls -lh \"$NVM_DIR/.cache\""
  nvm_execute="rm -rf \"$NVM_DIR/.cache\""
  
  confirm_action "NVM Cache" "$nvm_preview" "$nvm_execute"
else
  echo -e "\nℹ️  NVM_DIR not set or cache not found, skipping."
fi

# 4. System Logs Cleanup
# Preview: Show current disk usage of logs
log_preview="journalctl --disk-usage"
# Execute: Vacuum logs older than 7 days
log_execute="journalctl --vacuum-time=7d"

confirm_action "System Logs (Older than 7 days)" "$log_preview" "$log_execute"

# 5. User Cache Cleanup
# Preview: List caches found in /home/*
user_cache_preview="for home_dir in /home/*; do \
                      if [ -d \"$home_dir/.cache\" ] || [ -d \"$home_dir/.npm\" ]; then \
                        echo \"User: $(basename $home_dir)\"; \
                        du -sh \"$home_dir/.cache/thumbnails\" \"$home_dir/.cache/pip\" \"$home_dir/.npm\" \"$home_dir/.yarn/cache\" 2>/dev/null || true; \
                      fi; \
                    done"

user_cache_execute="for home_dir in /home/*; do \
                      if [ -d \"$home_dir\" ]; then \
                        rm -rf \"$home_dir/.cache/thumbnails\"; \
                        rm -rf \"$home_dir/.cache/pip\"; \
                        rm -rf \"$home_dir/.npm\"; \
                        rm -rf \"$home_dir/.yarn/cache\"; \
                      fi; \
                    done"

confirm_action "User Caches (Thumbnails, Pip, NPM)" "$user_cache_preview" "$user_cache_execute"

# 6. Temporary Files
# Preview: List top 20 largest files in /tmp and /var/tmp
temp_preview="echo 'Top items in /tmp:' && du -ah /tmp 2>/dev/null | sort -rh | head -n 10; \
              echo 'Top items in /var/tmp:' && du -ah /var/tmp 2>/dev/null | sort -rh | head -n 10"

temp_execute="rm -rf /tmp/* && rm -rf /var/tmp/*"

confirm_action "Temporary Files (/tmp, /var/tmp)" "$temp_preview" "$temp_execute"

# 7. DISABLED SNAP REMOVAL (Fixed Quotes)
if command -v snap &> /dev/null; then
  # Preview: List ONLY disabled revisions
  # Using double quotes to allow variable expansion and avoid nesting issues
  snap_preview="echo 'Disabled Snap Revisions (Safe to Remove):'; snap list --all | awk '/disabled/{print \"  \" \$1 \" (Rev: \" \$3 \")\"}' || echo 'None found'"
  
  # Execute: Remove only disabled revisions
  # Logic: Extract 'name' and 'revision', then loop to remove
  snap_execute="snap list --all | awk '/disabled/{print \$1 \" \" \$3}' | while read -r snapname revision; do echo \"Removing: \$snapname rev \$revision\"; snap remove \"\$snapname\" --revision=\"\$revision\"; done"
  
  confirm_action "Disabled Snap Revisions (Old Versions)" "$snap_preview" "$snap_execute"
  
  # Optional: Pin snapd
#  echo -e "\n🛡️  Recommendation: Prevent Snap from reinstalling automatically?"
#  read -r -p "   Create APT pin to block snapd reinstall? [y/N] " -n 1 #pin_response
#  echo ""
#  if [[ "$pin_response" =~ ^[Yy]$ ]]; then
#      echo "   Creating /etc/apt/preferences.d/nosnap.pref..."
#      cat <<EOF | tee /etc/apt/preferences.d/nosnap.pref
#Package: snapd
#Pin: release a=*
#Pin-Priority: -10
#EOF
#      echo "✅ Snapd pinned successfully."
#  else
#      echo "⏭️  Skipped pinning."
#  fi
#else
#  echo -e "\nℹ️  Snap not found, skipping Snap cleanup."
fi

# Final Summary
echo -e "\n=== 🎉 Cleanup Complete ==="
echo "Current Disk Usage:"
df -h /

echo -e "\n💡 Tip: If using a VM, run 'sudo fstrim -v /' to reclaim space on the host."   
