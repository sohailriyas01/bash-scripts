#!/usr/bin/env bash
# disk-usage-alert.sh
# Alert when disk usage on any filesystem exceeds a threshold.
# Default threshold: 90 (%)
# Usage:
#   ./disk-usage-alert.sh                # uses default threshold 90%
#   ./disk-usage-alert.sh -t 80          # set threshold to 80%
#   MAILTO=admin@example.com ./disk-usage-alert.sh
#   ./disk-usage-alert.sh -c "/usr/local/bin/custom-alert.sh"

set -uo pipefail

THRESHOLD=90
CUSTOM_CMD=""
# Filesystem types to ignore (space separated). Adjust if needed.
IGNORE_FSTYPES="tmpfs devtmpfs squashfs overlay"

usage() {
  cat <<EOF
Usage: $0 [-t threshold_percent] [-c "command-to-run-on-alert"]
  -t   Threshold percent (integer). Default: $THRESHOLD
  -c   Command to run when an alert is raised. The following placeholders are replaced:
         {mount} {percent} {avail} {device}
       Example: -c "echo 'Alert {mount} {percent}%'; /usr/bin/logger 'disk alert {mount} {percent}%'" 
  Environment:
    MAILTO - if set and mailx (or sendmail) available, a mail will be sent with the alert.
EOF
  exit 2
}

while getopts ":t:c:h" opt; do
  case $opt in
    t) THRESHOLD="$OPTARG" ;;
    c) CUSTOM_CMD="$OPTARG" ;;
    h) usage ;;
    \?) echo "Invalid option -$OPTARG" >&2; usage ;;
  esac
done

# Validate threshold numeric
if ! [[ "$THRESHOLD" =~ ^[0-9]+$ ]]; then
  echo "Threshold must be an integer percentage (e.g. 90)." >&2
  exit 2
fi

ALERTS=()
# Use POSIX-compatible df output with -P
# Columns: Filesystem 1024-blocks Used Available Capacity Mounted on
# We'll skip filesystems with types in IGNORE_FSTYPES
# To get fstype, use "df -PT"
while IFS= read -r line; do
  # skip header
  [[ "$line" =~ ^Filesystem ]] && continue

  # Parse using awk to be safe with spaces in mount points
  # df -PT prints: Filesystem Type 1024-blocks Used Available Capacity Mounted on
  device=$(awk '{print $1}' <<<"$line")
  fstype=$(awk '{print $2}' <<<"$line")
  used_pct=$(awk '{print $6}' <<<"$line" | tr -d '%')
  mountpoint=$(awk '{ for(i=7;i<=NF;i++) printf $i (i<NF?OFS:""); print "" }' <<<"$line")
  avail=$(awk '{print $5}' <<<"$line")

  # ignore certain fs types
  for t in $IGNORE_FSTYPES; do
    if [ "$fstype" = "$t" ]; then
      continue 2
    fi
  done

  # sanity checks
  if ! [[ "$used_pct" =~ ^[0-9]+$ ]]; then
    continue
  fi

  if [ "$used_pct" -ge "$THRESHOLD" ]; then
    ALERTS+=("$device|$mountpoint|$used_pct|$avail|$fstype")
  fi
done < <(df -PT 2>/dev/null)

if [ "${#ALERTS[@]}" -eq 0 ]; then
  # No alerts
  exit 0
fi

# Build alert body
HOSTNAME=$(hostname)
NOW=$(date -u +"%Y-%m-%d %H:%M:%SZ")
BODY="Disk usage alert on $HOSTNAME at $NOW
Threshold: ${THRESHOLD}%

"

for a in "${ALERTS[@]}"; do
  IFS='|' read -r dev mnt pct avail fstype <<<"$a"
  BODY+="Device: $dev
Mount:  $mnt
Type:   $fstype
Used:   ${pct}% 
Avail:  ${avail}
----
"
done

# Print to stdout/stderr
echo "==== DISK USAGE ALERT ===="
echo "$BODY"
echo "==========================" >&2

# Try to send mail if MAILTO is set and mailx or sendmail exists
if [ -n "${MAILTO-}" ]; then
  if command -v mailx >/dev/null 2>&1; then
    printf "%s\n" "$BODY" | mailx -s "Disk usage alert: ${HOSTNAME}" "$MAILTO" || true
  elif command -v sendmail >/dev/null 2>&1; then
    printf "Subject: Disk usage alert: %s\n\n%s\n" "$HOSTNAME" "$BODY" | sendmail "$MAILTO" || true
  else
    echo "MAILTO is set but no mailx/sendmail found. Skipping email." >&2
  fi
fi

# Run custom command if provided. Replace placeholders.
if [ -n "$CUSTOM_CMD" ]; then
  for a in "${ALERTS[@]}"; do
    IFS='|' read -r dev mnt pct avail fstype <<<"$a"
    cmd="${CUSTOM_CMD//\{mount\}/$mnt}"
    cmd="${cmd//\{percent\}/$pct}"
    cmd="${cmd//\{avail\}/$avail}"
    cmd="${cmd//\{device\}/$dev}"
    # shellcheck disable=SC2086
    eval "$cmd" || echo "Custom command failed: $cmd" >&2
  done
fi

# Exit non-zero to indicate alert happened
exit 1
