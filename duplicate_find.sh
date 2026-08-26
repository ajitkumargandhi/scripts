#!/bin/bash

# Duplicate File Finder & Remover (By Name & Size)
# Features: Generates a report, asks for confirmation, removes duplicates safely.

set -e

# --- Configuration ---
REPORT_FILE="duplicate_report_$(date +%F_%H-%M-%S).txt"
TARGET_DIR="${1:-.}" # Default to current directory if no argument provided

echo "=== 🔍 Duplicate File Scanner ==="
echo "Target Directory: $TARGET_DIR"
echo "Report File: $REPORT_FILE"
echo "-----------------------------------------"

# Check if directory exists
if [ ! -d "$TARGET_DIR" ]; then
    echo "❌ Error: Directory '$TARGET_DIR' does not exist."
    exit 1
fi

# --- Step 1: Scan and Identify Duplicates ---
echo "📊 Scanning for duplicates (Name + Size)..."

# Create a temporary file to store file info: "Size|Filename|FullPath"
TEMP_FILE=$(mktemp)
trap "rm -f $TEMP_FILE" EXIT

# Find all files, extract Size, Filename, and Full Path
# Using -printf for speed and accuracy
find "$TARGET_DIR" -type f -printf "%s|%f|%p\n" 2>/dev/null | sort -t'|' -k2,2 -k1,1n > "$TEMP_FILE"

# Identify duplicates using awk
# Logic: Group by Filename (field 2) and Size (field 1). If count > 1, it's a duplicate.
declare -A seen_files
declare -a duplicate_groups
current_group=()
last_key=""

# Process the sorted list to find groups
while IFS='|' read -r size name path; do
    key="${name}|${size}"
    
    if [ "$key" == "$last_key" ]; then
        # Same name and size as previous -> Duplicate found
        current_group+=("$path")
    else
        # New file name/size combination
        if [ ${#current_group[@]} -gt 1 ]; then
            # Save the previous group if it had duplicates
            duplicate_groups+=("$(IFS=';'; echo "${current_group[*]}")")
        fi
        # Reset group with the new file
        current_group=("$path")
        last_key="$key"
    fi
done < "$TEMP_FILE"

# Don't forget the last group
if [ ${#current_group[@]} -gt 1 ]; then
    duplicate_groups+=("$(IFS=';'; echo "${current_group[*]}")")
fi

# --- Step 2: Generate Report ---
echo "📝 Generating report..."
{
    echo "DUPLICATE FILES REPORT"
    echo "Generated: $(date)"
    echo "Directory: $TARGET_DIR"
    echo "-----------------------------------------"
    echo ""
    
    if [ ${#duplicate_groups[@]} -eq 0 ]; then
        echo "✅ No duplicates found based on Name and Size."
    else
        echo "Found ${#duplicate_groups[@]} groups of duplicate files:"
        echo ""
        group_num=1
        for group in "${duplicate_groups[@]}"; do
            echo "--- Group $group_num ---"
            IFS=';' read -ra files <<< "$group"
            for file in "${files[@]}"; do
                size=$(stat -c%s "$file" 2>/dev/null || echo "Unknown")
                echo "  [KEEP] $file ($size bytes)" # By default, we mark the first as KEEP
            done
            echo ""
            ((group_num++))
        done
    fi
} | tee "$REPORT_FILE"

# --- Step 3: Confirmation & Removal ---
if [ ${#duplicate_groups[@]} -eq 0 ]; then
    exit 0
fi

echo ""
read -r -p "❓ Do you want to REMOVE the duplicate copies (keeping the first one in each group)? [y/N] " -n 1 response
echo ""

if [[ "$response" =~ ^[Yy]$ ]]; then
    echo "🗑️  Starting removal process..."
    removed_count=0
    
    for group in "${duplicate_groups[@]}"; do
        IFS=';' read -ra files <<< "$group"
        
        # The first file in the array is the "Original" (kept)
        # The rest are duplicates (to be removed)
        original="${files[0]}"
        
        for ((i=1; i<${#files[@]}; i++)); do
            dup_file="${files[$i]}"
            if [ -f "$dup_file" ]; then
                echo "   Removing: $dup_file"
                rm -v "$dup_file"
                ((removed_count++))
            fi
        done
    done
    
    echo ""
    echo "✅ Cleanup Complete!"
    echo "   Total files removed: $removed_count"
    echo "   Report saved to: $REPORT_FILE"
else
    echo "⏭️  Removal skipped. Report saved to: $REPORT_FILE"
fi

# --- Step 3: Confirmation & Removal (Fixed) ---
if [ ${#duplicate_groups[@]} -eq 0 ]; then
    echo "✅ No duplicates to remove."
    exit 0
fi

echo ""
read -r -p "❓ Do you want to REMOVE the duplicate copies (keeping the first one in each group)? [y/N] " -n 1 response
echo ""

if [[ "$response" =~ ^[Yy]$ ]]; then
    echo -e "\n🗑️  Starting removal process..."
    removed_count=0
    
    # Iterate through each group of duplicates
    for group in "${duplicate_groups[@]}"; do
        # Split the group string back into an array using ';' as delimiter
        IFS=';' read -ra files <<< "$group"
        
        # Safety check: Ensure we have at least 2 files (1 original + 1 duplicate)
        if [ ${#files[@]} -lt 2 ]; then
            continue
        fi

        # The first file is the "Original" (KEEP)
        # Loop starts from index 1 to delete the rest
        for ((i=1; i<${#files[@]}; i++)); do
            dup_file="${files[$i]}"
            
            # Double check file exists before deleting
            if [ -f "$dup_file" ]; then
                echo "   Removing: $dup_file"
                rm -v "$dup_file"
                ((removed_count++))
            else
                echo "   ⚠️  Skipped (not found): $dup_file"
            fi
        done
    done
    
    echo ""
    echo -e "\033[0;32m✅ Cleanup Complete!\033[0m"
    echo "   Total files removed: $removed_count"
    echo "   Report saved to: $REPORT_FILE"
else
    echo "⏭️  Removal skipped. Report saved to: $REPORT_FILE"
fi

