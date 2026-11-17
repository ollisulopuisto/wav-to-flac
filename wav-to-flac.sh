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
set -o pipefail

MAX_JOBS=""
DRY_RUN=1 # 1=dry run mode (default), 0=real run mode
LOG_FILE="$HOME/wav2flac_log.txt"

# --- Logging Function ---
log() {
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local message="$timestamp - ${LOG_CONTEXT:+[$LOG_CONTEXT] }$1"
    printf '%s\n' "$message" | tee -a "$LOG_FILE"
}

# --- Convert Audio (WAV/AIFF) to FLAC ---
# Compare decoded audio, not just file existence or size. Strict decoding
# rejects truncated streams; matching hashes also reject a valid but wrong FLAC.
audio_hash() {
    ffmpeg -hide_banner -loglevel error -xerror -err_detect explode -nostdin \
        -i "$1" -map 0:a:0 -c:a pcm_s32le -f hash -hash sha256 -
}

convert_audio_to_flac() (
    local audio_file="$1"
    local LOG_CONTEXT="$audio_file"
    local flac_file="${audio_file}.flac"
    local candidate="$flac_file" temp_file="" source_hash converted_hash
    local delete_flac=0 ffmpeg_output mod_time
    trap 'if [[ -n "$temp_file" ]]; then rm -f -- "$temp_file"; fi' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    log "Processing: $audio_file"
    if [[ -L "$flac_file" ]]; then
        log "ERROR: Refusing symlink output: $flac_file"
        return 1
    fi
    if [[ -e "$flac_file" || -L "$flac_file" ]]; then
        log "Checking existing FLAC: $flac_file"
    else
        temp_file=$(mktemp "${flac_file}.tmp.XXXXXX") || return 1
        candidate="$temp_file"
        mod_time=$(stat -c "%Y" "$audio_file" 2>/dev/null || stat -f "%m" "$audio_file") || return 1
        if ! ffmpeg_output=$(ffmpeg -y -hide_banner -loglevel error -nostdin \
            -i "$audio_file" -map_metadata 0 -c:a flac -threads 1 \
            -compression_level 4 -f flac "$temp_file" 2>&1); then
            log "ERROR: ffmpeg conversion failed for: $audio_file: $ffmpeg_output"
            return 1
        fi
        if [[ "$OSTYPE" == "darwin"* ]]; then
            touch -t "$(date -r "$mod_time" "+%Y%m%d%H%M.%S")" "$temp_file" || return 1
        else
            touch -d "@$mod_time" "$temp_file" || return 1
        fi
    fi
    source_hash=$(audio_hash "$audio_file") || { log "ERROR: Could not verify source: $audio_file"; return 1; }
    if [[ "$(head -c 4 "$candidate")" != fLaC ]]; then
        log "ERROR: Output is not a FLAC stream: $audio_file"
        return 1
    fi
    local source_properties converted_properties
    source_properties=$(ffprobe -v error -select_streams a:0 \
        -show_entries stream=sample_rate,channels -of csv=p=0 "$audio_file") || return 1
    converted_properties=$(ffprobe -v error -select_streams a:0 \
        -show_entries stream=sample_rate,channels -of csv=p=0 "$candidate") || return 1
    if [[ -z "$source_properties" || "$source_properties" != "$converted_properties" ]]; then
        log "ERROR: FLAC stream properties differ: $audio_file"
        return 1
    fi
    converted_hash=$(audio_hash "$candidate") || { log "ERROR: Invalid FLAC for: $audio_file"; return 1; }
    if [[ -z "$source_hash" || "$source_hash" != "$converted_hash" ]]; then
        log "ERROR: FLAC audio does not match source: $audio_file"
        return 1
    fi
    if [[ -n "$temp_file" ]]; then
        if [[ $DRY_RUN -eq 1 ]]; then
            flac_file="$temp_file"
            delete_flac=1
        else
            # Both paths are in the same directory/filesystem.
            if [[ -e "$flac_file" || -L "$flac_file" ]]; then
                log "ERROR: Output appeared during conversion: $flac_file"
                return 1
            fi
            mv -n -- "$temp_file" "$flac_file" || return 1
            [[ ! -e "$temp_file" ]] || return 1
            temp_file=""
        fi
        log "Conversion verified: $audio_file"
    fi
    # Always compare sizes if FLAC file exists
    if [[ -f "$flac_file" ]]; then
        local audio_size flac_size
        audio_size=$(stat -c "%s" "$audio_file" 2>/dev/null || stat -f "%z" "$audio_file") || return 1
        flac_size=$(stat -c "%s" "$flac_file" 2>/dev/null || stat -f "%z" "$flac_file") || return 1
        
        if (( audio_size > flac_size )); then
            local saved_mb=$(( (audio_size - flac_size) / 1024 / 1024 ))
            log "Audio file is larger than FLAC (saving ~${saved_mb}MB)"
            
            # Only move to trash in real run mode
            if [[ $DRY_RUN -eq 1 ]]; then
                log "DRY RUN: Would move $audio_file to trash"
            else
                # Find trash directory - start with parent directories
                local trash_dir=""
                local dir
                dir=$(dirname "$audio_file")
                
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
                    return 1
                else
                    move_to_trash "$audio_file" "$base_dir" "$trash_dir" || return 1
                fi
            fi
        else
            log "Audio file is smaller or equal to FLAC - keeping both files"
        fi
        
        # In dry run mode, delete the FLAC file we just created
        if [[ $delete_flac -eq 1 ]]; then
            log "DRY RUN: Removing temporary FLAC file"
            if ! rm -- "$flac_file"; then
                log "WARNING: Could not remove temporary FLAC file: $flac_file"
            else
                log "Successfully removed temporary FLAC file"
            fi
        fi
    fi
)

# --- Move file to trash while preserving directory structure ---
move_to_trash() {
    local file_path="$1"
    local base_dir="$2"
    local trash_dir="$3"
    
    # find returns absolute paths beneath base_dir; strip that literal prefix.
    local rel_path="${file_path#"${base_dir%/}"/}"
    local target_dir
    target_dir=$(dirname "$trash_dir/$rel_path")
    if ! mkdir -p "$target_dir"; then
        log "ERROR: Could not create directory structure in trash"
        return 1
    fi

    # Move the file to the structured trash location
    log "Moving audio to trash: $file_path -> $target_dir/"
    if [[ -e "$target_dir/$(basename "$file_path")" || -L "$target_dir/$(basename "$file_path")" ]]; then
        log "ERROR: Trash destination exists for: $file_path"
        return 1
    fi
    mv -n -- "$file_path" "$target_dir/" 2>> "$LOG_FILE"
    
    if [[ $? -ne 0 || -e "$file_path" ]]; then
        log "ERROR: Could not move $file_path to trash"
        return 1
    else
        log "Successfully moved to trash: $file_path"
        return 0
    fi
}

# --- Main Function ---
main() {
    local opt
    # Parse command-line options
    while getopts ":nj:h" opt; do
        case $opt in
            n) DRY_RUN=0 ;;
            j) MAX_JOBS="$OPTARG" ;;
            h) printf '%s\n' 'Usage: wav-to-flac.sh [-n] [-j 1..8] [directory]' \
                   '  Default: dry run, at most two workers.' \
                   '  -n  Verify outputs and move larger originals to #recycle.' \
                   '  -j  Set the worker limit (1..8).' \
                   '  -h  Show this help.'; return 0 ;;
            :) echo "Missing value: -$OPTARG" >&2; return 1 ;;
            \?) echo "Invalid option: -$OPTARG" >&2; exit 1 ;;
        esac
    done
    shift $((OPTIND-1))
    if [[ -n "$MAX_JOBS" && ! "$MAX_JOBS" =~ ^[1-8]$ ]]; then
        echo "ERROR: -j must be between 1 and 8" >&2
        return 1
    fi
    
    for tool in ffmpeg ffprobe; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            echo "ERROR: Required command not found: $tool" >&2
            return 1
        fi
    done
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
    
    # The traversal never enters the recycle bin.
    log "Finding WAV and AIFF files to process..."
    local total_files
    total_files=$(find "$base_dir" -type d -name '#recycle' -prune -o -type f \( -iname "*.wav" -o -iname "*.aif" -o -iname "*.aiff" \) -print0 | tr -cd '\0' | wc -c) || return 1
    log "Found $total_files audio files to process"
    
    if [ "$total_files" -gt 0 ]; then
        local max_jobs="$MAX_JOBS" cpu_count=1
        if [[ -z "$max_jobs" ]]; then
            if command -v nproc >/dev/null 2>&1; then
                cpu_count=$(nproc)
            elif command -v sysctl >/dev/null 2>&1; then
                cpu_count=$(sysctl -n hw.ncpu 2>/dev/null) || cpu_count=1
            fi
            [[ "$cpu_count" =~ ^[1-9][0-9]*$ ]] || cpu_count=1
            max_jobs=2
            [[ "$cpu_count" == 1 ]] && max_jobs=1
        fi
        log "Worker limit: $max_jobs"
        # The loop and both batch waits share the worker-owning subshell.
        # Bounded batches intentionally keep compatibility with macOS Bash 3.2.
        if ! find "$base_dir" -type d -name '#recycle' -prune -o -type f \
            \( -iname "*.wav" -o -iname "*.aif" -o -iname "*.aiff" \) -print0 | {
            count=0
            failed=0
            pids=()
            while IFS= read -r -d '' audio_file; do
                ((count++))
                log "[$count/$total_files] Processing: $audio_file"
                convert_audio_to_flac "$audio_file" &
                pids+=("$!")
                if (( ${#pids[@]} >= max_jobs )); then
                    for pid in "${pids[@]}"; do wait "$pid" || failed=1; done
                    pids=()
                fi
            done
            for pid in "${pids[@]}"; do wait "$pid" || failed=1; done
            exit "$failed"
        }; then
            log "ERROR: Conversion process failed; check per-file errors"
            return 1
        fi
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
