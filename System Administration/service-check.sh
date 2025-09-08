#!/usr/bin/env bash
# service-check.sh
# Verify if critical services are running. Try restart and report.
# Usage:
#   ./service-check.sh nginx docker kubelet         # check listed services
#   ./service-check.sh -a                           # check built-in critical services
#   ./service-check.sh -r nginx                     # try restart on failures
set -euo pipefail

RESTART=false
SERVICES=()

while getopts ":ar" opt; do
  case $opt in
    a) SERVICES=(nginx docker kubelet) ;;
    r) RESTART=true ;;
    *) echo "Usage: $0 [-a] [-r] [service...]" ; exit 2 ;;
  esac
done
shift $((OPTIND-1))
# Append any services provided as args
if [ $# -gt 0 ]; then SERVICES+=("$@";); fi
# Default if none
if [ ${#SERVICES[@]} -eq 0 ]; then SERVICES=(nginx docker kubelet); fi

has_cmd(){ command -v "$1" >/dev/null 2>&1; }

use_systemctl=false
if has_cmd systemctl; then use_systemctl=true; fi

results=()

for s in "${SERVICES[@]}"; do
  status="unknown"
  if $use_systemctl; then
    if systemctl list-units --full -all | grep -qE "^$s\.service"; then
      if systemctl is-active --quiet "$s"; then status="active"; else status="inactive"; fi
    else
      # maybe not a unit named exactly service
      if systemctl is-active --quiet "$s"; then status="active"; else status="inactive"; fi
    fi
  else
    if has_cmd service; then
      out=$(service "$s" status 2>&1 || true)
      if echo "$out" | grep -iq "running"; then status="active"; else status="inactive"; fi
    else
      status="no-tool"
    fi
  fi

  echo "Service: $s Status: $status"
  results+=("$s:$status")

  if [ "$status" != "active" ] && $RESTART; then
    echo "Attempting restart: $s"
    if $use_systemctl; then
      sudo systemctl restart "$s" && sleep 1
      if systemctl is-active --quiet "$s"; then echo "Restart OK: $s"; else echo "Restart FAILED: $s"; fi
    else
      if has_cmd service; then
        sudo service "$s" restart || true
        sleep 1
        out=$(service "$s" status 2>&1 || true)
        if echo "$out" | grep -iq "running"; then echo "Restart OK: $s"; else echo "Restart FAILED: $s"; fi
      else
        echo "Cannot restart $s, no service manager available."
      fi
    fi
  fi
done

# Exit non-zero if any critical service is not active
for r in "${results[@]}"; do
  s=${r%%:*}; st=${r#*:}
  if [ "$st" != "active" ]; then exit 1; fi
done

exit 0
