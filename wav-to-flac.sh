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

# --- Convert WAV to FLAC ---
convert_wav_to_flac() {
    local wav_file="$1"
    local flac_file="${wav_file%.wav}.flac"
    
    log "Processing: $wav_file"
    
    # Check if output file already exists
    if [[ -f "$flac_file" ]]; then
        log "FLAC file already exists: $flac_file - skipping conversion"
    else
        # Save original file timestamps
        local mod_time=$(stat -c "%y" "$wav_file" 2>/dev/null || stat -f "%m" "$wav_file")
        local access_time=$(stat -c "%x" "$wav_file" 2>/dev/null || stat -f "%a" "$wav_file")
        
        # Perform the conversion using ffmpeg with metadata preservation
        ffmpeg -y -hide_banner -loglevel error -i "$wav_file" -map_metadata 0 -c:a flac -compression_level 4 "$flac_file" 2>> "$LOG_FILE"
        
        if [[ $? -ne 0 ]]; then
            log "ERROR: ffmpeg conversion failed for: $wav_file"
            return 1
        fi
        
        # Preserve original timestamps on the new file
        if [[ "$OSTYPE" == "darwin"* ]]; then
            # macOS
            touch -t "$(date -r "$mod_time" "+%Y%m%d%H%M.%S")" "$flac_file"
        else
            # Linux
            touch -d "@$mod_time" "$flac_file"
        fi
        
        log "Conversion successful: $wav_file -> $flac_file (with metadata preserved)"
    fi
    
    # Compare sizes
    local wav_size=$(stat -c "%s" "$wav_file" 2>/dev/null || stat -f "%z" "$wav_file")
    local flac_size=$(stat -c "%s" "$flac_file" 2>/dev/null || stat -f "%z" "$flac_file")
    
    if (( wav_size > flac_size )); then
        local saved_mb=$(( (wav_size - flac_size) / 1024 / 1024 ))
        log "WAV file is larger than FLAC (saving ~${saved_mb}MB)"
        
        if [[ $DRY_RUN -eq 0 ]]; then
            # Find trash directory - start with parent directories
            local trash_dir=""
            local dir=$(dirname "$wav_file")
            
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
                log "ERROR: Trash directory not found for: $wav_file"
            else
                log "Moving WAV to trash: $wav_file -> $trash_dir/"
                mv "$wav_file" "$trash_dir/" 2>> "$LOG_FILE"
                
                if [[ $? -ne 0 ]]; then
                    log "ERROR: Could not move $wav_file to trash"
                else
                    log "Successfully moved to trash: $wav_file"
                fi
            fi
        else
            log "DRY RUN: Would move $wav_file to trash"
        fi
    else
        log "WAV file is smaller or equal to FLAC - keeping both files"
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
    log "Finding WAV files to process..."
    local total_files=$(find "$base_dir" -type f -iname "*.wav" | wc -l)
    log "Found $total_files WAV files to process"
    
    if [ "$total_files" -gt 0 ]; then
        # Process files one by one using find's -exec
        local count=0
        find "$base_dir" -type f -iname "*.wav" -print0 | 
        while IFS= read -r -d $'\0' wav_file; do
            ((count++))
            log "[$count/$total_files] Processing file"
            convert_wav_to_flac "$wav_file"
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