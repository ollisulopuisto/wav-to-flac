#!/bin/bash

# ------------------------------------------------------------------------------
# Script: wav-to-flac.sh
# Purpose: Converts WAV files to FLAC format with metadata preservation
# Environment: Optimized for Synology DSM 7
# Features:
#   - Preserves file metadata and timestamps
#   - Compares file sizes between WAV and FLAC
#   - Optionally moves WAV files to trash if FLAC is smaller
#   - Supports parallel processing for faster conversion
#   - Includes detailed logging
# Usage: ./wav-to-flac.sh [-n] <base_directory>
#   -n: Disable dry-run mode (will move WAV files if FLAC is smaller)
# ------------------------------------------------------------------------------

set -e # Exit immediately if a command exits with non-zero status

# --- Configuration Variables ---
readonly PARALLEL_PROCESSES=4
DRY_RUN=1 # 1=dry run mode (default), 0=real run mode

# --- Logging Function ---
log() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local message="$timestamp - $1"
    echo "$message" | tee -a "$LOG_FILE"
}

# --- Find Trash Directory ---
find_trash_dir() {
    local file_path="$1"
    local current_dir
    
    # Absolute path
    current_dir=$(cd "$(dirname "$file_path")" && pwd)
    
    # First check for #recycle in current or parent directories
    while [[ "$current_dir" != "/" ]]; do
        if [[ -d "$current_dir/#recycle" ]]; then
            echo "$current_dir/#recycle"
            return 0
        fi
        current_dir=$(dirname "$current_dir")
    done
    
    # Second check for @recycle at volume root
    volume_root=$(echo "$file_path" | cut -d'/' -f1-2)
    if [[ -d "$volume_root/#recycle" ]]; then
        echo "$volume_root/#recycle"
        return 0
    fi
    
    # Default to /volume1/#recycle or /volume2/#recycle
    for vol in "/volume1" "/volume2"; do
        if [[ -d "$vol/#recycle" ]]; then
            echo "$vol/#recycle"
            return 0
        fi
    done
    
    # Last resort - check if a backup trash exists
    for vol in "/volume1/backup" "/volume2/backup"; do
        if [[ -d "$vol/#recycle" ]]; then
            echo "$vol/#recycle"
            return 0
        fi
    done
    
    # No trash found
    echo ""
    return 1
}

# --- Convert WAV to FLAC ---
convert_wav_to_flac() {
    local wav_file="$1"
    local flac_file="${wav_file%.wav}.flac" # Better naming - remove .wav extension
    
    log "Processing: $wav_file"
    
    # Check if output file already exists
    if [[ -f "$flac_file" ]]; then
        log "FLAC file already exists: $flac_file - skipping conversion"
        # Still compare sizes for potential trash operations
    else
        # Perform the conversion using ffmpeg
        ffmpeg -hide_banner -loglevel error -i "$wav_file" -map_metadata 0 -c:a flac -compression_level 12 "$flac_file" 2>> "$LOG_FILE"
        
        if [[ $? -ne 0 ]]; then
            log "ERROR: ffmpeg conversion failed for: $wav_file"
            return 1
        fi
        
        log "Conversion successful: $wav_file -> $flac_file"
    fi
    
    # File size comparison and trash logic
    local wav_size=$(stat -c "%s" "$wav_file" 2>/dev/null || stat -f "%z" "$wav_file")
    local flac_size=$(stat -c "%s" "$flac_file" 2>/dev/null || stat -f "%z" "$flac_file")
    
    if (( wav_size > flac_size )); then
        local saved_space=$(( (wav_size - flac_size) / 1024 / 1024 ))
        log "WAV file is larger than FLAC (saving ~${saved_space}MB)."
        
        if [[ "$DRY_RUN" -eq 0 ]]; then
            local trash_dir=$(find_trash_dir "$wav_file")
            
            if [[ -z "$trash_dir" ]]; then
                log "ERROR: Trash directory not found for: $wav_file"
            else
                log "Moving to trash: $wav_file -> $trash_dir/"
                mv "$wav_file" "$trash_dir/" 2>> "$LOG_FILE"
                
                if [[ $? -ne 0 ]]; then
                    log "ERROR: Could not move $wav_file to trash."
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

# --- Process Directory ---
process_directory() {
    local base_dir="$1"
    local count=0
    local total_files=0
    
    # Count total files for progress reporting
    total_files=$(find "$base_dir" -type f -iname "*.wav" | wc -l)
    log "Found $total_files WAV files to process"
    
    # Process all WAV files in parallel
    find "$base_dir" -type f -iname "*.wav" -print0 | 
    while IFS= read -r -d $'\0' wav_file; do
        # Process in background with a semaphore to limit parallelism
        ((count++))
        
        # Show progress
        log "[$count/$total_files] Queuing: $wav_file"
        
        # Run in background with controlled parallelism
        (
            convert_wav_to_flac "$wav_file"
        ) &
        
        # Limit number of parallel processes
        if [[ $(jobs -r | wc -l) -ge $PARALLEL_PROCESSES ]]; then
            wait -n
        fi
    done
    
    # Wait for all background processes to finish
    wait
}

# --- Main Script Logic ---
main() {
    # Parse command-line options
    while getopts ":n" opt; do
        case $opt in
            n)
                DRY_RUN=0
                ;;
            \?)
                echo "Invalid option: -$OPTARG" >&2
                exit 1
                ;;
        esac
    done
    shift $((OPTIND-1))
    
    # Set base_dir *after* processing options
    local base_dir="${1:-.}" # Default to current directory if not specified
    
    # Convert to absolute path
    base_dir=$(cd "$base_dir" 2>/dev/null && pwd)
    if [[ $? -ne 0 || -z "$base_dir" ]]; then
        echo "ERROR: Base directory does not exist or is not accessible: $1"
        exit 1
    fi
    
    # Validate ffmpeg is installed
    if ! command -v ffmpeg &> /dev/null; then
        echo "ERROR: ffmpeg is not installed."
        exit 1
    fi
    
    # Create log file in the user's home directory
    LOG_FILE="$HOME/wav2flac_log.txt"
    touch "$LOG_FILE"
    
    # Export variables for subprocess access
    export LOG_FILE
    export DRY_RUN
    
    # Start message
    log "========================================"
    log "Starting WAV to FLAC conversion script"
    log "Mode: $(if [[ $DRY_RUN -eq 1 ]]; then echo "DRY RUN"; else echo "REAL RUN"; fi)"
    log "Base directory: $base_dir"
    log "Parallel processes: $PARALLEL_PROCESSES"
    log "========================================"
    
    # Process the directory
    process_directory "$base_dir"
    
    # Completion message
    log "========================================"
    log "Conversion process completed"
    log "Log file: $LOG_FILE"
    log "========================================"
}

# Execute main function
main "$@"
