#!/bin/bash

# ------------------------------------------------------------------------------
# Script: wav-to-flac.sh
# Purpose: Converts WAV files to FLAC format with metadata preservation
# Features:
#   - Preserves file metadata and timestamps
#   - Compares file sizes between WAV and FLAC
#   - Optionally deletes WAV files if FLAC is smaller (when not in dry-run mode)
#   - Supports parallel processing for faster conversion
#   - Includes detailed logging
# Usage: ./wav-to-flac.sh [-n] -d <base_directory>
#   -n: Disable dry-run mode (will delete WAV files if FLAC is smaller)
#   -d: Specify the base directory containing WAV files
# ------------------------------------------------------------------------------

# --- Configuration Variables ---
trash_dir="/volume1/your/music/directory/#recycle"  # Directory for moved WAV files (MUST BE CONFIGURED)
log_file="${base_dir}/wav2flac_log.txt"  # Log file path (will be updated after base_dir is set)
parallel_processes=4  # Number of conversion processes to run simultaneously

# --- Logging Function ---#!/bin/bash

# ------------------------------------------------------------------------------
# Script: wav-to-flac.sh
# Purpose: Converts WAV files to FLAC format with metadata preservation
# Features:
#   - Preserves file metadata and timestamps
#   - Compares file sizes between WAV and FLAC
#   - Optionally deletes WAV files if FLAC is smaller (when not in dry-run mode)
#   - Supports parallel processing for faster conversion
#   - Includes detailed logging
# Usage: ./wav-to-flac.sh [-n] -d <base_directory>
#   -n: Disable dry-run mode (will delete WAV files if FLAC is smaller)
#   -d: Specify the base directory containing WAV files
# ------------------------------------------------------------------------------

# --- Configuration Variables ---
trash_dir="/volume1/your/music/directory/#recycle"  # Directory for moved WAV files (MUST BE CONFIGURED)
log_file="${base_dir}/wav2flac_log.txt"  # Log file path (will be updated after base_dir is set)
parallel_processes=4  # Number of conversion processes to run simultaneously

# --- Logging Function ---
# Outputs messages to both console and log file with timestamp
log() {
  local message="$1"
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $message"
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $message" >> "$log_file"
}

# --- Core Conversion Function ---
# Processes a single WAV file to convert it to FLAC
convert_wav_to_flac() {
  local wav_file="$1"
  local flac_file="${wav_file%.wav}.flac"  # Generate FLAC filename by replacing extension

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

  # Perform the conversion using ffmpeg with maximum compression
  # -map_metadata 0 preserves metadata from the source file
  ffmpeg -i "$wav_file" -map_metadata 0 -c:a flac -compression_level 12 "$flac_file" 2>> "$log_file"

  # Check if conversion was successful
  if [ $? -ne 0 ]; then
    log "ERROR: ffmpeg conversion failed for: $wav_file"
    return 1
  fi

  log "Conversion successful: $wav_file -> $flac_file"
  touch -r "$wav_file" "$flac_file"  # Preserve the timestamp from original file

  # Compare file sizes to determine if conversion saved space
  local wav_size=$(stat -c%s "$wav_file")
  local flac_size=$(stat -c%s "$flac_file")

  log "WAV size: $wav_size bytes"
  log "FLAC size: $flac_size bytes"

  # Handle WAV file if FLAC is smaller
  if (( wav_size > flac_size )); then
    log "WAV file is larger than FLAC."
    if [[ "$dry_run" -eq 0 ]]; then
      # In non-dry-run mode, move WAV to trash directory
      if [ ! -d "$trash_dir" ]; then
        log "ERROR: Trash directory not found: $trash_dir"
      else
        mv "$wav_file" "$trash_dir" 2>>"$log_file"
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
    log "WAV file is smaller or equal to FLAC."
  fi

  # In dry-run mode, clean up the created FLAC files
  if [[ "$dry_run" -eq 1 ]]; then
        rm "$flac_file"
    if [ $? -ne 0 ]; then
      log "ERROR: Could not remove flac file $flac_file."
    else
      log "Removed flac file: $flac_file"
    fi
  fi

  return 0
}

# --- Main Script Logic ---

# Initialize default values
dry_run=1  # Default to dry run mode (safer)
base_dir=""  # Will be set via command line

# Parse command-line options
# -n: Disable dry run (will delete WAV files)
# -d: Set the base directory for conversion
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
      exit 1
      ;;
    :)
      echo "Option -$OPTARG requires an argument." >&2
      exit 1
      ;;
  esac
done
shift $((OPTIND-1))  # Remove processed options

# Validate inputs and requirements
# Check if base directory was provided
if [ -z "$base_dir" ]; then
  echo "ERROR: Base directory must be provided with -d option."
  echo "Usage: $0 [-n] -d <base_directory>"
  exit 1
fi

# Check if ffmpeg is available
if ! command -v ffmpeg &> /dev/null; then
  echo "ERROR: ffmpeg is not installed."
  exit 1
fi

# Verify base directory exists
if [ ! -d "$base_dir" ]; then
    echo "ERROR: base directory $base_dir does not exist"
    exit 1
fi

# Update log file path with the confirmed base directory
log_file="${base_dir}/wav2flac_log.txt"
touch "$log_file"  # Create log file if it doesn't exist

# Begin conversion process
log "Starting WAV to FLAC conversion script."

# Display mode information
if [[ "$dry_run" -eq 1 ]]; then
  log "Dry run mode enabled. WAV files will NOT be deleted."
else
  log "WARNING: Dry run mode disabled. WAV files WILL be deleted if larger than FLAC."
fi

# Find all WAV files and process them in parallel
# -print0 and -0 handle filenames with spaces
# -P sets the number of parallel processes
find "$base_dir" -type f -iname "*.wav" -print0 | xargs -0 -P "$parallel_processes" bash -c 'convert_wav_to_flac "$1"' _

log "Conversion process completed."

exit 0
# Outputs messages to both console and log file with timestamp
log() {
  local message="$1"
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $message"
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $message" >> "$log_file"
}

# --- Core Conversion Function ---
# Processes a single WAV file to convert it to FLAC
convert_wav_to_flac() {
  local wav_file="$1"
  local flac_file="${wav_file%.wav}.flac"  # Generate FLAC filename by replacing extension

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

  # Perform the conversion using ffmpeg with maximum compression
  # -map_metadata 0 preserves metadata from the source file
  ffmpeg -i "$wav_file" -map_metadata 0 -c:a flac -compression_level 12 "$flac_file" 2>> "$log_file"

  # Check if conversion was successful
  if [ $? -ne 0 ]; then
    log "ERROR: ffmpeg conversion failed for: $wav_file"
    return 1
  fi

  log "Conversion successful: $wav_file -> $flac_file"
  touch -r "$wav_file" "$flac_file"  # Preserve the timestamp from original file

  # Compare file sizes to determine if conversion saved space
  local wav_size=$(stat -c%s "$wav_file")
  local flac_size=$(stat -c%s "$flac_file")

  log "WAV size: $wav_size bytes"
  log "FLAC size: $flac_size bytes"

  # Handle WAV file if FLAC is smaller
  if (( wav_size > flac_size )); then
    log "WAV file is larger than FLAC."
    if [[ "$dry_run" -eq 0 ]]; then
      # In non-dry-run mode, move WAV to trash directory
      if [ ! -d "$trash_dir" ]; then
        log "ERROR: Trash directory not found: $trash_dir"
      else
        mv "$wav_file" "$trash_dir" 2>>"$log_file"
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
    log "WAV file is smaller or equal to FLAC."
  fi

  # In dry-run mode, clean up the created FLAC files
  if [[ "$dry_run" -eq 1 ]]; then
        rm "$flac_file"
    if [ $? -ne 0 ]; then
      log "ERROR: Could not remove flac file $flac_file."
    else
      log "Removed flac file: $flac_file"
    fi
  fi

  return 0
}

# --- Main Script Logic ---

# Initialize default values
dry_run=1  # Default to dry run mode (safer)
base_dir=""  # Will be set via command line

# Parse command-line options
# -n: Disable dry run (will delete WAV files)
# -d: Set the base directory for conversion
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
      exit 1
      ;;
    :)
      echo "Option -$OPTARG requires an argument." >&2
      exit 1
      ;;
  esac
done
shift $((OPTIND-1))  # Remove processed options

# Validate inputs and requirements
# Check if base directory was provided
if [ -z "$base_dir" ]; then
  echo "ERROR: Base directory must be provided with -d option."
  echo "Usage: $0 [-n] -d <base_directory>"
  exit 1
fi

# Check if ffmpeg is available
if ! command -v ffmpeg &> /dev/null; then
  echo "ERROR: ffmpeg is not installed."
  exit 1
fi

# Verify base directory exists
if [ ! -d "$base_dir" ]; then
    echo "ERROR: base directory $base_dir does not exist"
    exit 1
fi

# Update log file path with the confirmed base directory
log_file="${base_dir}/wav2flac_log.txt"
touch "$log_file"  # Create log file if it doesn't exist

# Begin conversion process
log "Starting WAV to FLAC conversion script."

# Display mode information
if [[ "$dry_run" -eq 1 ]]; then
  log "Dry run mode enabled. WAV files will NOT be deleted."
else
  log "WARNING: Dry run mode disabled. WAV files WILL be deleted if larger than FLAC."
fi

# Find all WAV files and process them in parallel
# -print0 and -0 handle filenames with spaces
# -P sets the number of parallel processes
find "$base_dir" -type f -iname "*.wav" -print0 | xargs -0 -P "$parallel_processes" bash -c 'convert_wav_to_flac "$1"' _

log "Conversion process completed."

exit 0#!/bin/bash

# Script to convert WAV files to FLAC, preserve metadata, compare sizes, and optionally delete the WAV.
# Supports dry-run mode and custom base directory via command-line options.

# --- Configuration ---
trash_dir="/volume1/your/music/directory/#recycle"  # Example: /volume1/music/#recycle.  STILL NEEDS TO BE SET.
log_file="${base_dir}/wav2flac_log.txt"  # Will be updated later.
parallel_processes=4  # Number of parallel processes for ffmpeg.

# --- Functions ---

log() {
  local message="$1"
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $message"
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $message" >> "$log_file"
}

convert_wav_to_flac() {
  local wav_file="$1"
  local flac_file="${wav_file%.wav}.flac"

  log "Processing: $wav_file"

  if [ ! -f "$wav_file" ]; then
    log "ERROR: WAV file not found: $wav_file"
    return 1
  fi

  if [ -f "$flac_file" ]; then
    log "WARNING: FLAC file already exists: $flac_file"
    return 1
  fi

  ffmpeg -i "$wav_file" -map_metadata 0 -c:a flac -compression_level 12 "$flac_file" 2>> "$log_file"

  if [ $? -ne 0 ]; then
    log "ERROR: ffmpeg conversion failed for: $wav_file"
    return 1
  fi

  log "Conversion successful: $wav_file -> $flac_file"
  touch -r "$wav_file" "$flac_file"

  local wav_size=$(stat -c%s "$wav_file")
  local flac_size=$(stat -c%s "$flac_file")

  log "WAV size: $wav_size bytes"
  log "FLAC size: $flac_size bytes"

  if (( wav_size > flac_size )); then
    log "WAV file is larger than FLAC."
    if [[ "$dry_run" -eq 0 ]]; then
      if [ ! -d "$trash_dir" ]; then
        log "ERROR: Trash directory not found: $trash_dir"
      else
        mv "$wav_file" "$trash_dir" 2>>"$log_file"
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
    log "WAV file is smaller or equal to FLAC."
  fi

    # remove flac if dry_run
  if [[ "$dry_run" -eq 1 ]]; then
        rm "$flac_file"
    if [ $? -ne 0 ]; then
      log "ERROR: Could not remove flac file $flac_file."
    else
      log "Removed flac file: $flac_file"
    fi
  fi

  return 0
}

# --- Main Script ---

# Default to dry run.
dry_run=1
base_dir=""  # Initialize base_dir.

# Parse command-line options.
while getopts ":nd:" opt; do
  case $opt in
    n)
      dry_run=0
      ;;
    d)
      base_dir="$OPTARG"
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

# Check if base directory was provided.
if [ -z "$base_dir" ]; then
  echo "ERROR: Base directory must be provided with -d option."
  echo "Usage: $0 [-n] -d <base_directory>"
  exit 1
fi

# Check if ffmpeg is installed.
if ! command -v ffmpeg &> /dev/null; then
  echo "ERROR: ffmpeg is not installed."
  exit 1
fi

# check if base directory exists
if [ ! -d "$base_dir" ]; then
    echo "ERROR: base directory $base_dir does not exist"
    exit 1
fi

# Now that base_dir is set, update log_file.
log_file="${base_dir}/wav2flac_log.txt"
touch "$log_file" #create log file

log "Starting WAV to FLAC conversion script."

if [[ "$dry_run" -eq 1 ]]; then
  log "Dry run mode enabled. WAV files will NOT be deleted."
else
  log "WARNING: Dry run mode disabled. WAV files WILL be deleted if larger than FLAC."
fi

find "$base_dir" -type f -iname "*.wav" -print0 | xargs -0 -P "$parallel_processes" bash -c 'convert_wav_to_flac "$1"' _

log "Conversion process completed."

exit 0
