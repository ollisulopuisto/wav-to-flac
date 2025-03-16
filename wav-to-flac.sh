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
# Usage: ./wav-to-flac.sh [-n] -d <base_directory>
#   -n: Disable dry-run mode (will move WAV files if FLAC is smaller)
#   -d: Specify the base directory containing WAV files
# ------------------------------------------------------------------------------

# --- Configuration Variables ---
# Standard Synology DSM 7 recycle bin path (adjust volume number if needed)
trash_dir="/volume1/@recycle"  
base_dir=""
log_file=""
parallel_processes=4

# --- Logging Function ---
log() {
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  echo "${timestamp} - $1"
  echo "${timestamp} - $1" >> "$log_file"
}

# --- Core Conversion Function ---
convert_wav_to_flac() {
  # Get environment variables passed from parent process
  local dry_run="$DRY_RUN"
  local trash_dir="$TRASH_DIR"
  local log_file="$LOG_FILE"
  
  local wav_file="$1"
  local flac_file="${wav_file%.wav}.flac"
  
  log "Processing: $wav_file"

  # Check if source WAV file exists
  if [ ! -f "$wav_file" ]; then
    log "ERROR: WAV file not found: $wav_file"
    return 1
  fi

  # Avoid overwriting existing FLAC files
  if [ -f "$flac_file" ]; then
    log "WARNING: FLAC file already exists: $flac_file"
    return 1
  fi

  # Perform the conversion using ffmpeg
  ffmpeg -i "$wav_file" -map_metadata 0 -c:a flac -compression_level 12 "$flac_file" 2>> "$log_file"

  if [ $? -ne 0 ]; then
    log "ERROR: ffmpeg conversion failed for: $wav_file"
    return 1
  fi

  log "Conversion successful: $wav_file -> $flac_file"
  touch -r "$wav_file" "$flac_file"  # Preserve timestamp

  # Compatible file size check for Synology DSM 7 (BusyBox)
  local wav_size=""
  local flac_size=""
  
  # Try both GNU and BSD stat syntax
  wav_size=$(stat -c "%s" "$wav_file" 2>/dev/null || stat -f "%z" "$wav_file")
  flac_size=$(stat -c "%s" "$flac_file" 2>/dev/null || stat -f "%z" "$flac_file")
  
  if [ -z "$wav_size" ] || [ -z "$flac_size" ]; then
    log "ERROR: Could not determine file sizes"
    return 1
  fi

  log "WAV size: $wav_size bytes"
  log "FLAC size: $flac_size bytes"

  # Handle WAV file if FLAC is smaller
  if (( wav_size > flac_size )); then
    log "WAV file is larger than FLAC."
    if [[ "$dry_run" -eq 0 ]]; then
      if [ ! -d "$trash_dir" ]; then
        log "ERROR: Trash directory not found: $trash_dir"
      else
        mv "$wav_file" "$trash_dir/" 2>>"$log_file"
        if [ $? -ne 0 ]; then
          log "ERROR: Could not move $wav_file to trash."
        else
          log "Moved to trash: $wav_file"
        fi
      fi
    else
      log "Dry run: Would move to trash: $wav_file"
    fi
  else
    log "WAV file is smaller or equal to FLAC - keeping both files"
  fi

  # In dry-run mode, clean up the created FLAC files
  if [[ "$dry_run" -eq 1 ]]; then
    rm "$flac_file" 2>/dev/null
    if [ $? -eq 0 ]; then
      log "Removed temporary FLAC file: $flac_file"
    else
      log "ERROR: Could not remove FLAC file $flac_file."
    fi
  fi

  return 0
}

# --- Main Script Logic ---

# Initialize default values
dry_run=1  # Default to dry run mode

# Parse command-line options
while getopts ":nd:" opt; do
  case $opt in
    n)
      dry_run=0  # Disable dry run
      ;;
    d)
      base_dir="$OPTARG"  # Set base directory
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      echo "Usage: $0 [-n] -d <base_directory>" >&2
      exit 1
      ;;
    :)
      echo "Option -$OPTARG requires an argument." >&2
      echo "Usage: $0 [-n] -d <base_directory>" >&2
      exit 1
      ;;
  esac
done
shift $((OPTIND-1))  # Remove processed options

# Validate inputs and requirements
if [ -z "$base_dir" ]; then
  echo "ERROR: Base directory must be provided with -d option."
  echo "Usage: $0 [-n] -d <base_directory>"
  exit 1
fi

# Check if ffmpeg is available
if ! command -v ffmpeg &> /dev/null; then
  echo "ERROR: ffmpeg is not installed. Please install it via Synology Package Center."
  exit 1
fi

# Verify base directory exists
if [ ! -d "$base_dir" ]; then
  echo "ERROR: Base directory $base_dir does not exist"
  exit 1
fi

# Update log file path with the confirmed base directory
log_file="${base_dir}/wav2flac_log.txt"
touch "$log_file"  # Create log file if it doesn't exist

# Begin conversion process
log "Starting WAV to FLAC conversion script."
log "Processing directory: $base_dir"
log "Trash directory: $trash_dir"

# Display mode information
if [[ "$dry_run" -eq 1 ]]; then
  log "Dry run mode enabled. WAV files will NOT be moved."
else
  log "WARNING: Dry run mode disabled. WAV files WILL be moved to trash if larger than FLAC."
fi

# Export variables for subprocesses
export DRY_RUN=$dry_run
export TRASH_DIR=$trash_dir
export LOG_FILE=$log_file

# Create a process pool for parallel execution
log "Using $parallel_processes parallel conversion processes"

# Find all WAV files and process them
find "$base_dir" -type f -iname "*.wav" -print0 | 
  xargs -0 -P "$parallel_processes" -I{} bash -c 'convert_wav_to_flac "$@"' _ "{}"

log "Conversion process completed."
exit 0
