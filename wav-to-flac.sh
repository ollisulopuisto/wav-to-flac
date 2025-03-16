#!/bin/bash

# ------------------------------------------------------------------------------
# Script: wav-to-flac.sh
# Purpose: Converts WAV files to FLAC format with metadata preservation
# Environment: Optimized for Synology DSM 7
# Features:
#   - Preserves file metadata and timestamps
#   - Compares file sizes between WAV and FLAC
#   - Optionally moves WAV files to trash if FLAC is smaller
#   - Includes detailed logging
# Usage: ./wav-to-flac.sh [-n] <base_directory>
#   -n: Disable dry-run mode (will move WAV files if FLAC is smaller)
# ------------------------------------------------------------------------------

# --- Configuration Variables ---
DRY_RUN=1 # 1=dry run mode (default), 0=real run mode
LOG_FILE="$HOME/wav2flac_log.txt"

# --- Logging Function ---
log() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local message="$timestamp - $1"
    echo "$message" | tee -a "$LOG_FILE"
}

# --- Convert Audio (WAV/AIFF) to FLAC ---
convert_audio_to_flac() {
    local audio_file="$1"
    local flac_file="${audio_file}.flac"
    local delete_flac=0
    local format=$(echo "$audio_file" | grep -i -E '\.(wav|aif|aiff)$' | tr '[:upper:]' '[:lower:]')
    
    log "Processing: $audio_file"
    
    # Check if output file already exists
    if [[ -f "$flac_file" ]]; then
        log "FLAC file already exists: $flac_file - skipping conversion"
    else
        # Remember to delete FLAC if in dry run mode
        if [[ $DRY_RUN -eq 1 ]]; then
            delete_flac=1
        fi
        
        # Save original file timestamps
        local mod_time=$(stat -c "%Y" "$audio_file" 2>/dev/null || stat -f "%m" "$audio_file")
        
        # Perform the actual conversion using ffmpeg with metadata preservation
        ffmpeg_output=$(ffmpeg -y -hide_banner -loglevel error -nostdin -i "$audio_file" -map_metadata 0 -c:a flac -compression_level 4 "$flac_file" 2>&1)
        ffmpeg_status=$?

        if [[ $ffmpeg_status -ne 0 ]]; then
            log "ERROR: ffmpeg conversion failed for: $audio_file"
            log "FFMPEG ERROR: $ffmpeg_output"
            return 1
        fi
        
        # Preserve original timestamps on the new file
        if [[ "$OSTYPE" == "darwin"* ]]; then
            # macOS
            touch -t "$(date -r "$mod_time" "+%Y%m%d%H%M.%S")" "$flac_file"
        else
            # Linux/Synology - try different methods
            if [[ "$mod_time" =~ ^[0-9]+$ ]]; then
                # If mod_time is only digits (Unix timestamp)
                touch -d "@$mod_time" "$flac_file" 2>/dev/null
            else
                # If mod_time is a formatted date string
                touch -d "$mod_time" "$flac_file" 2>/dev/null || 
                touch "$flac_file" 2>/dev/null
            fi
        fi
        
        log "Conversion successful: $audio_file -> $flac_file (with metadata preserved)"
    fi
    
    # Always compare sizes if FLAC file exists
    if [[ -f "$flac_file" ]]; then
        local audio_size=$(stat -c "%s" "$audio_file" 2>/dev/null || stat -f "%z" "$audio_file")
        local flac_size=$(stat -c "%s" "$flac_file" 2>/dev/null || stat -f "%z" "$flac_file")
        
        if (( audio_size > flac_size )); then
            local saved_mb=$(( (audio_size - flac_size) / 1024 / 1024 ))
            log "Audio file is larger than FLAC (saving ~${saved_mb}MB)"
            
            # Only move to trash in real run mode
            if [[ $DRY_RUN -eq 1 ]]; then
                log "DRY RUN: Would move $audio_file to trash"
            else
                # Find trash directory - start with parent directories
                local trash_dir=""
                local dir=$(dirname "$audio_file")
                
                # Search up the directory tree for #recycle
                while [[ "$dir" != "/" && -z "$trash_dir" ]]; do
                    if [[ -d "$dir/#recycle" ]]; then
                        trash_dir="$dir/#recycle"
                    fi
                    dir=$(dirname "$dir")
                done
                
                # If not found, check volume roots
                if [[ -z "$trash_dir" ]]; then
                    for vol in "/volume1" "/volume2" "/volume1/backup" "/volume2/backup"; do
                        if [[ -d "$vol/#recycle" ]]; then
                            trash_dir="$vol/#recycle"
                            break
                        fi
                    done
                fi
                
                if [[ -z "$trash_dir" ]]; then
                    log "ERROR: Trash directory not found for: $audio_file"
                else
                    move_to_trash "$audio_file" "$base_dir" "$trash_dir"
                fi
            fi
        else
            log "Audio file is smaller or equal to FLAC - keeping both files"
        fi
        
        # In dry run mode, delete the FLAC file we just created
        if [[ $delete_flac -eq 1 ]]; then
            log "DRY RUN: Removing temporary FLAC file"
            rm "$flac_file"
            if [[ $? -ne 0 ]]; then
                log "WARNING: Could not remove temporary FLAC file: $flac_file"
            else
                log "Successfully removed temporary FLAC file"
            fi
        fi
    fi
}

# --- Move file to trash while preserving directory structure ---
move_to_trash() {
    local file_path="$1"
    local base_dir="$2"
    local trash_dir="$3"
    
    # Get the relative path from base_dir to file_path
    local rel_path=$(realpath --relative-to="$base_dir" "$file_path" 2>/dev/null || 
                    echo "${file_path#$base_dir/}")
    
    # Create target directory in trash
    local target_dir="$trash_dir/$(dirname "$rel_path")"
    
    # Create directory structure if it doesn't exist
    if [[ ! -d "$target_dir" ]]; then
        log "Creating directory structure in trash: $target_dir"
        mkdir -p "$target_dir" 2>/dev/null
        
        if [[ $? -ne 0 ]]; then
            log "ERROR: Could not create directory structure in trash"
            return 1
        fi
    fi
    
    # Move the file to the structured trash location
    log "Moving audio to trash: $file_path -> $target_dir/"
    mv "$file_path" "$target_dir/" 2>> "$LOG_FILE"
    
    if [[ $? -ne 0 ]]; then
        log "ERROR: Could not move $file_path to trash"
        return 1
    else
        log "Successfully moved to trash: $file_path"
        return 0
    fi
}

# --- Main Function ---
main() {
    # Parse command-line options
    while getopts ":n" opt; do
        case $opt in
            n) DRY_RUN=0 ;;
            \?) echo "Invalid option: -$OPTARG" >&2; exit 1 ;;
        esac
    done
    shift $((OPTIND-1))
    
    # Set base directory (default to current directory)
    local base_dir="${1:-.}"
    
    # Convert to absolute path
    base_dir=$(cd "$base_dir" 2>/dev/null && pwd)
    if [[ $? -ne 0 || -z "$base_dir" ]]; then
        echo "ERROR: Base directory does not exist: $1"
        exit 1
    fi
    
    # Initialize log file
    touch "$LOG_FILE"
    
    # Start message
    log "========================================"
    log "Starting WAV to FLAC conversion script"
    log "Mode: $(if [[ $DRY_RUN -eq 1 ]]; then echo "DRY RUN"; else echo "REAL RUN"; fi)"
    log "Base directory: $base_dir"
    log "========================================"
    
    # Use find with exec to process files - more reliable with spaces in filenames
    log "Finding WAV and AIFF files to process..."
    local total_files=$(find "$base_dir" \( -iname "*.wav" -o -iname "*.aif" -o -iname "*.aiff" \) | wc -l)
    log "Found $total_files audio files to process"
    
    if [ "$total_files" -gt 0 ]; then
        # Process files one by one using find's -exec
        local count=0
        find "$base_dir" \( -iname "*.wav" -o -iname "*.aif" -o -iname "*.aiff" \) -print0 | 
        while IFS= read -r -d $'\0' audio_file; do
            ((count++))
            log "[$count/$total_files] Processing file"
            convert_audio_to_flac "$audio_file"
        done
    else
        log "No WAV files found to process."
    fi
    
    # Completion message
    log "========================================"
    log "Conversion process completed"
    log "Log file: $LOG_FILE"
    log "========================================"
}

# Execute main function
main "$@"
