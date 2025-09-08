#!/usr/bin/env bash
# uptime-report.sh
# Generate system uptime report
# Usage:
#   ./uptime-report.sh           # prints report
#   ./uptime-report.sh -o file   # write to file
set -euo pipefail

OUTFILE=""
while getopts ":o:" opt; do
  case $opt in
    o) OUTFILE="$OPTARG" ;;
    *) echo "Usage: $0 [-o outfile]"; exit 2 ;;
  esac
done

if [[ -n "$OUTFILE" ]]; then exec >"$OUTFILE"; fi

echo "Uptime report for: $(hostname) generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
echo
echo "System uptime and load:"
uptime
echo
echo "Last boot:"
who -b
echo
echo "Recent reboots (last 5):"
last reboot -n 5
echo
echo "Users currently logged in:"
who
echo
echo "Top 10 longest-running processes (by elapsed time):"
ps -eo pid,etime,cmd --sort=etime | tail -n 10
echo
echo "Top 5 CPU consumers:"
ps -eo pid,pcpu,pmem,cmd --sort=-pcpu | head -n 6
echo
echo "Top 5 memory consumers:"
ps -eo pid,pcpu,pmem,rss,cmd --sort=-pmem | head -n 6

exit 0
