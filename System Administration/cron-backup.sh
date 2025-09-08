#!/usr/bin/env bash
# cron-backup.sh
# Backup and restore cron jobs (user crontabs + /etc/cron.*)
# Usage:
#   ./cron-backup.sh backup /path/to/archive.tar.gz
#   ./cron-backup.sh restore /path/to/archive.tar.gz
set -euo pipefail

if [ $# -lt 2 ]; then
  echo "Usage: $0 {backup|restore} /path/to/archive.tar.gz" >&2
  exit 2
fi

MODE=$1
ARCHIVE=$2
TMPDIR=$(mktemp -d)

cleanup(){ rm -rf "$TMPDIR"; }
trap cleanup EXIT

case "$MODE" in
  backup)
    echo "Backing up user crontabs..."
    mkdir -p "$TMPDIR/crontabs"
    for u in $(awk -F: '($3>=1000)||($3==0){print $1}' /etc/passwd); do
      if crontab -l -u "$u" >/dev/null 2>&1; then
        crontab -l -u "$u" >"$TMPDIR/crontabs/$u.cron" || true
      else
        # store empty marker
        : >"$TMPDIR/crontabs/$u.cron"
      fi
    done

    echo "Copying /etc/crontab and /etc/cron.*"
    mkdir -p "$TMPDIR/etc"
    cp -a /etc/crontab "$TMPDIR/etc/" 2>/dev/null || true
    cp -a /etc/cron.* "$TMPDIR/etc/" 2>/dev/null || true

    echo "Creating archive: $ARCHIVE"
    tar -C "$TMPDIR" -czf "$ARCHIVE" .
    echo "Backup complete: $ARCHIVE"
    ;;

  restore)
    if [ ! -f "$ARCHIVE" ]; then echo "Archive not found: $ARCHIVE" >&2; exit 3; fi
    echo "Extracting archive..."
    tar -C "$TMPDIR" -xzf "$ARCHIVE"
    # Restore system files first (backup originals)
    if [ -d "$TMPDIR/etc" ]; then
      echo "Restoring /etc/crontab and /etc/cron.* (backing up originals to /etc/*.bak)..."
      for f in "$TMPDIR"/etc/*; do
        fn=$(basename "$f")
        if [ -e "/etc/$fn" ]; then sudo cp -a "/etc/$fn" "/etc/$fn.bak.$(date +%s)"; fi
        sudo cp -a "$f" "/etc/$fn"
      done
    fi

    # Restore user crontabs
    if [ -d "$TMPDIR/crontabs" ]; then
      echo "Restoring user crontabs..."
      for c in "$TMPDIR/crontabs"/*.cron; do
        u=$(basename "$c" .cron)
        echo "Installing crontab for user: $u"
        # safe install
        if [[ -s "$c" ]]; then
          sudo crontab -u "$u" "$c" || echo "Failed to install crontab for $u" >&2
        else
          # empty file means clear crontab
          sudo crontab -r -u "$u" || true
        fi
      done
    fi
    echo "Restore complete."
    ;;

  *)
    echo "Invalid mode. Use backup or restore." >&2
    exit 2
    ;;
esac

exit 0
