#!/usr/bin/env bash
# system-update.sh
# Auto update + patch system
# Usage:
#   ./system-update.sh            # interactive default behavior
#   ./system-update.sh -y         # auto-yes to package manager prompts
#   ./system-update.sh -n         # dry-run (where supported)
#   ./system-update.sh -r         # reboot if kernel updated
set -euo pipefail

AUTO_YES=false
DRY_RUN=false
REBOOT_IF_KERNEL=false

while getopts ":ynr" opt; do
  case $opt in
    y) AUTO_YES=true ;;
    n) DRY_RUN=true ;;
    r) REBOOT_IF_KERNEL=true ;;
    *) echo "Usage: $0 [-y] [-n] [-r]"; exit 2 ;;
  esac
done

has_cmd(){ command -v "$1" >/dev/null 2>&1; }

echo "Detecting package manager..."
PKG=""
if has_cmd apt-get; then PKG="apt"; elif has_cmd dnf; then PKG="dnf"; elif has_cmd yum; then PKG="yum"; elif has_cmd zypper; then PKG="zypper"; elif has_cmd pacman; then PKG="pacman"; else echo "No supported package manager found." >&2; exit 3; fi
echo "Using: $PKG"

# Remember current kernel version to detect kernel upgrade
CUR_KERNEL=$(uname -r)

case "$PKG" in
  apt)
    if $DRY_RUN; then
      sudo apt-get -s update
      sudo apt-get -s upgrade
    else
      sudo apt-get update
      if $AUTO_YES; then sudo DEBIAN_FRONTEND=noninteractive apt-get -y upgrade; else sudo apt-get upgrade; fi
      if $AUTO_YES; then sudo DEBIAN_FRONTEND=noninteractive apt-get -y dist-upgrade; else sudo apt-get dist-upgrade; fi
      sudo apt-get -y autoremove
      sudo apt-get -y autoclean
    fi
    ;;
  dnf)
    if $DRY_RUN; then sudo dnf -y check-update; else sudo dnf -y upgrade --refresh; sudo dnf -y autoremove; fi
    ;;
  yum)
    if $DRY_RUN; then sudo yum -y check-update; else sudo yum -y update; fi
    ;;
  zypper)
    if $DRY_RUN; then sudo zypper --non-interactive refresh; else sudo zypper --non-interactive update; fi
    ;;
  pacman)
    if $DRY_RUN; then echo "pacman does not have a full dry-run here"; else sudo pacman -Syu --noconfirm; fi
    ;;
esac

NEW_KERNEL=$(uname -r)
if [ "$CUR_KERNEL" != "$NEW_KERNEL" ]; then
  echo "Kernel changed: $CUR_KERNEL -> $NEW_KERNEL"
  if $REBOOT_IF_KERNEL; then
    echo "Rebooting now..."
    sudo reboot
  else
    echo "Reboot recommended to apply kernel update."
  fi
else
  echo "No kernel change detected."
fi

echo "Update complete."
exit 0
