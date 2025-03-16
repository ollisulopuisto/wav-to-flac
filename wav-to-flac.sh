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

# --- Configuration Variables ---
log_file="${base_dir}/wav2flac_log.txt"
parallel_processes=4
dry_run=1

# --- Helper Functions ---
# Get volume path from a given file
get_volume_path() {
  local file="$1"
  # Extract the volume part (e.g., /volume1)
  echo "$file" | cut -d'/' -f1,2
}

# --- Logging Function ---
log() {
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  echo "${timestamp} - $1" >> "$log_file"
}

# --- Core Conversion Function ---
convert_wav_to_flac() {
  local wav_file="$1"
  local flac_file="${wav_file}.flac"

  log "Processing: $wav_file"

  # Perform the conversion using ffmpeg
  ffmpeg -i "$wav_file" -map_metadata 0 -c:a flac -compression_level 12 "$flac_file" 2>> "$log_file"

  if [ $? -ne 0 ]; then
    log "ERROR: ffmpeg conversion failed for: $wav_file"
    return 1
  fi

  log "Conversion successful: $wav_file -> $flac_file"

  # File size comparison and trash logic
  local wav_size=$(stat -c "%s" "$wav_file" 2>/dev/null || stat -f "%z" "$wav_file")
  local flac_size=$(stat -c "%s" "$flac_file" 2>/dev/null || stat -f "%z" "$flac_file")

  if (( wav_size > flac_size )); then
    log "WAV file is larger than FLAC."
    if [[ "$dry_run" -eq 0 ]]; then
      # Dynamically determine trash directory
      local volume_path=$(get_volume_path "$wav_file")
      local trash_dir="${volume_path}/@recycle"

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
      log "Dry run: Would move $wav_file to trash"
    fi
  else
    log "WAV file is smaller or equal to FLAC - keeping both files"
  fi
}

# --- Main Script Logic ---

# Parse command-line options
while getopts ":n" opt; do
  case $opt in
    n)
      dry_run=0
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      exit 1
      ;;
    :)
      echo "Option -$OPTARG requires an argument." >&2
      exit 1
      ;;
  esac
done
shift $((OPTIND-1))

# Set base_dir *after* processing options
base_dir="$1"

# Validate inputs and requirements
if [ -z "$base_dir" ]; then
  echo "ERROR: Base directory must be provided."
  exit 1
fi

if ! command -v ffmpeg &> /dev/null; then
  echo "ERROR: ffmpeg is not installed."
  exit 1
fi

if [ ! -d "$base_dir" ]; then
  echo "ERROR: Base directory does not exist"
  exit 1
fi

touch "$log_file"

log "Starting WAV to FLAC conversion script."

find "$base_dir" -type f -iname "*.wav" -print0 | xargs -0 -P "$parallel_processes" convert_wav_to_flac

log "Conversion process completed."
exit 0
