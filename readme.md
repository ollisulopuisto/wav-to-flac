# WAV to FLAC Converter

A robust Bash script for converting WAV and AIFF audio files to FLAC format with metadata preservation, optimized for Synology NAS systems but works on Linux and macOS too.

## Features

- Converts WAV and AIFF files to FLAC format using ffmpeg (case insensitive)
- Preserves file metadata and timestamps during conversion
- Compares file sizes between original audio and FLAC formats
- Optionally moves original audio files to trash if FLAC is smaller (saves disk space)
- Includes detailed logging for tracking conversions
- Dry run mode to simulate conversion without changing files
- Safely traverses directories with spaces in filenames

## Requirements

- Bash shell
- ffmpeg (must be installed and available in PATH)
- Linux, macOS, or Synology DSM 7+

## Usage

Basic usage:

```
wav-to-flac.sh [options] [directory]
```

If no directory is specified, the current directory is used.

### Options

- `-n`: Disable dry-run mode (will actually move WAV files to trash if FLAC is smaller)

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

- In dry run mode, the script simulates the conversion process without creating or modifying any files. It provides estimates of space savings and logs the actions it *would* take.
- The script searches for a trash directory named `#recycle` in the parent directories of the WAV files, and in `/volume1`, `/volume2`, `/volume1/backup`, and `/volume2/backup`. If no trash directory is found, a warning is logged, and the WAV file is not moved.

## License

MIT License

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
