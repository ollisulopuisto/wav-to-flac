# WAV to FLAC Converter

A robust Bash script for converting WAV and AIFF audio files to FLAC format with metadata preservation, optimized for Synology NAS systems but works on Linux and macOS too.

## Features

- Converts WAV and AIFF files to FLAC format using ffmpeg (case insensitive)
- Preserves file metadata and timestamps during conversion
- Compares file sizes between original audio and FLAC formats
- Optionally moves original audio files to trash if FLAC is smaller (saves disk space)
- Includes detailed logging for tracking conversions
- Dry run mode converts temporarily to measure savings, but never moves originals
- Safely traverses directories with spaces in filenames

## Requirements

- Bash 3.2 or newer
- ffmpeg and ffprobe (both must be installed and available in PATH)
- Linux, macOS, or Synology DSM 7+

## Usage

Basic usage:

```
wav-to-flac.sh [options] [directory]
```

If no directory is specified, the current directory is used.

### Options

- `-n`: Disable dry-run mode (move original audio to trash only after verifying a smaller FLAC).
- `-j N`: Use 1 to 8 workers. The default is two, or one when only one CPU is available. Each encoder uses one thread.
- `-h`: Show help.

### Examples

1. Convert all WAV files in the current directory (dry run mode, no actual files moved):

```
./wav-to-flac.sh
```

2. Convert all WAV files in a specific directory (dry run mode):

```
./wav-to-flac.sh "/path/to/music/folder"
```

3. Convert files and move original WAV files to trash if FLAC is smaller:

```
./wav-to-flac.sh -n "/path/to/music/folder"
```

## File Naming

The script maintains the original filename and adds a `.flac` extension:

Original: file.wav → Converted: file.wav.flac
Original: file.aiff → Converted: file.aiff.flac
Original: file.AIF → Converted: file.AIF.flac

This preserves the original file name completely.

## Log File

The script creates a log file at `$HOME/wav2flac_log.txt` with detailed information about:

- Files processed
- Conversion status
- Space savings
- Files moved to trash (in non-dry run mode)
- Completion status

## Important Notes

- Dry run creates a unique adjacent temporary file, verifies it, measures savings, and removes it. It never publishes a new final FLAC or moves an original. Existing FLAC files remain untouched.
- New output is written to an adjacent temporary file and published with a same-filesystem rename only after verification. Failure or a caught interruption removes the unpublished temporary file. An uncatchable power loss or SIGKILL can leave `.flac.tmp.*` files; these are never accepted as finished output on reruns.
- Before moving any original, the script checks the FLAC signature, strictly decodes both files, and compares decoded PCM SHA-256 hashes plus sample rate and channel count. A truncated or different existing FLAC produces an error and leaves the original in place. Formats that cannot round-trip losslessly are refused rather than discarded.
- Original timestamps are applied to new output. Originals are moved only when the verified FLAC is smaller. A collision in the recycle bin is an error; nothing is overwritten.
- The traversal excludes `#recycle` directories. The script searches ancestors and known Synology volume roots for a recycle bin; a missing bin is an error for a real run that needs to move a file.
- All launched conversions finish before the command reports completion. Any failed conversion makes the command return nonzero, after waiting for its other workers. Per-file log lines include their source path. Batches intentionally wait for their slowest worker for Bash 3.2 compatibility; this is not a work-stealing pool.
- Verification reads both decoded streams and adds work. No wall-clock speedup is claimed for this safety fix.

## Tests

Run `bash -n wav-to-flac.sh`, `shellcheck wav-to-flac.sh`, and `python3 -m unittest discover -s tests -v` with ffmpeg/ffprobe available. Tests use generated audio and temporary recycle directories, not a real music library. They cover one-file, exact-batch and partial-batch completion; failed/truncated/wrong audio; dry runs; timestamps; cleanup on SIGTERM; bounds; and recycle collisions. CI runs the suite on Linux and macOS, whose `/bin/bash` exercises the Bash 3.2 path.

## License

MIT License

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
