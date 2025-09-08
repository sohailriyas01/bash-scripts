#!/usr/bin/env bash
# log-rotate.sh
# Simple log rotation & compression script
# Usage:
#   ./log-rotate.sh /var/log/myapp myapp.log 7
#
# Arguments:
#   $1 = log directory (e.g., /var/log/myapp)
#   $2 = log filename (e.g., myapp.log)
#   $3 = number of rotated logs to keep (default: 5)
#
# Result:
#   Rotates myapp.log -> myapp.log.1.gz -> myapp.log.2.gz ...
#   Keeps N archives, deletes older ones.

set -euo pipefail

# Parse args
LOG_DIR=${1:-}
LOG_FILE=${2:-}
KEEP=${3:-5}

if [[ -z "$LOG_DIR" || -z "$LOG_FILE" ]]; then
  echo "Usage: $0 <log_dir> <log_file> [keep_count]" >&2
  exit 2
fi

FULL_PATH="$LOG_DIR/$LOG_FILE"

if [[ ! -f "$FULL_PATH" ]]; then
  echo "Error: log file '$FULL_PATH' not found." >&2
  exit 1
fi

cd "$LOG_DIR"

echo "Rotating $FULL_PATH (keeping $KEEP archives)..."

# Step 1: Remove oldest archive if it exists
if [[ -f "$LOG_FILE.$KEEP.gz" ]]; then
  echo "Deleting old archive: $LOG_FILE.$KEEP.gz"
  rm -f "$LOG_FILE.$KEEP.gz"
fi

# Step 2: Shift older archives
for (( i=KEEP-1; i>=1; i-- )); do
  if [[ -f "$LOG_FILE.$i.gz" ]]; then
    echo "Renaming $LOG_FILE.$i.gz -> $LOG_FILE.$((i+1)).gz"
    mv "$LOG_FILE.$i.gz" "$LOG_FILE.$((i+1)).gz"
  fi
done

# Step 3: Rotate current log -> .1.gz
if [[ -s "$LOG_FILE" ]]; then
  echo "Archiving $LOG_FILE -> $LOG_FILE.1.gz"
  mv "$LOG_FILE" "$LOG_FILE.1"
  gzip -f "$LOG_FILE.1"
else
  echo "Log file is empty, skipping archive."
fi

# Step 4: Recreate empty log file
touch "$LOG_FILE"
chmod 644 "$LOG_FILE"

echo "Rotation complete."
