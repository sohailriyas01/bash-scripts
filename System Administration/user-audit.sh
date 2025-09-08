#!/usr/bin/env bash
# user-audit.sh
# Local user audit tool
#
# Features:
#  - Lists local user accounts (from /etc/passwd)
#  - Shows UID, GID, home, shell
#  - Shows last login (lastlog), last successful auth (last)
#  - Password status and expiry (chage) when available
#  - Sudo privileges (members of sudo, wheel, or sudoers file)
#  - SSH authorized_keys presence and summary
#  - Home dir ownership, permissions, unusual world-writeable or root-owned homes
#  - Account locked/disabled status (passwd -S)
#  - Active sessions (who)
#  - Running processes owned by the user (top 5 by RSS)
#  - Recent failed login attempts (lastb) if readable
#  - Optional JSON output
#
# Usage:
#   ./user-audit.sh                 # prints human-readable audit
#   ./user-audit.sh -u username     # audit single user
#   ./user-audit.sh -j              # output JSON
#   ./user-audit.sh -o /path/file   # write output to file
#
# Notes:
#  - Requires root to read some files like /var/log/lastlog or lastb and to run 'chage' for all users.
#  - Works on most Linux distributions.

set -euo pipefail

PROGNAME=$(basename "$0")
OUTFILE=""
JSON=false
SINGLE_USER=""

usage() {
  cat <<EOF
Usage: $PROGNAME [-u username] [-j] [-o outfile] [-h]
  -u username   Audit only this user
  -j            Output JSON (machine readable)
  -o outfile    Write output to file (otherwise prints to stdout)
  -h            Show this help
EOF
  exit 1
}

while getopts ":u:jo:h" opt; do
  case $opt in
    u) SINGLE_USER="$OPTARG" ;;
    j) JSON=true ;;
    o) OUTFILE="$OPTARG" ;;
    h) usage ;;
    *) usage ;;
  esac
done

# Helpers
timestamp() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

# Collect list of users to audit
get_users() {
  if [[ -n "$SINGLE_USER" ]]; then
    if getent passwd "$SINGLE_USER" >/dev/null; then
      printf "%s\n" "$SINGLE_USER"
    else
      echo "Error: user '$SINGLE_USER' not found" >&2
      exit 2
    fi
  else
    # Local accounts: uid >= 1000 and system accounts often < 1000.
    # Also include 0 (root).
    awk -F: '($3>=1000)||($3==0){print $1}' /etc/passwd | sort
  fi
}

# Check if a command exists
has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

# Check sudoers and group membership for sudo-like privileges
get_sudo_info() {
  local user="$1"
  local in_sudoers=false
  local in_group=false
  # Check common sudo groups
  for g in sudo wheel admin; do
    if getent group "$g" >/dev/null; then
      if id -nG "$user" | grep -qw "$g"; then
        in_group=true
      fi
    fi
  done

  # Check sudoers file for explicit entries (skipping includes parsing complexity)
  if [[ -r /etc/sudoers ]]; then
    if grep -E -v '^\s*#' /etc/sudoers | grep -E "\b${user}\b" >/dev/null 2>&1; then
      in_sudoers=true
    fi
  fi

  printf "%s|%s" "$in_group" "$in_sudoers"
}

# Summarize authorized_keys (counts keys and file age)
get_ssh_keys_info() {
  local home="$1"
  local auth="$home/.ssh/authorized_keys"
  if [[ -f "$auth" ]]; then
    local keys
    keys=$(grep -cve '^\s*$' "$auth" || true)
    local mtime
    mtime=$(date -u -r "$auth" +"%Y-%m-%dT%H:%M:%SZ")
    printf "%s|%s" "$keys" "$mtime"
  else
    printf "0|"
  fi
}

# Read failed attempts (requires root to read lastb)
get_failed_logins() {
  local user="$1"
  if has_cmd lastb && [[ -r /var/log/btmp ]]; then
    # Limit to last 20 entries for this user
    lastb -F "$user" 2>/dev/null | head -n 20 || true
  else
    echo "(no lastb available or not readable)"
  fi
}

# Main per-user audit
audit_user() {
  local user="$1"
  local pwline
  pwline=$(getent passwd "$user" || true)
  if [[ -z "$pwline" ]]; then
    return
  fi

  IFS=: read -r username passwd uid gid gecos home shell <<<"$pwline"

  # Basic
  local last_login last_success lastlog_entry
  if has_cmd lastlog; then
    lastlog_entry=$(lastlog -u "$user" 2>/dev/null | sed -n '2p' || true)
    last_login=$(printf "%s" "$lastlog_entry" | awk '{$1=$1; print}' )
  else
    last_login="(lastlog not available)"
  fi

  if has_cmd last; then
    last_success=$(last -n 1 "$user" 2>/dev/null | head -n 1 || true)
  else
    last_success="(last not available)"
  end

  # Password and expiry: chage output
  local passwd_status chage_info
  if has_cmd chage; then
    chage_info=$(chage -l "$user" 2>/dev/null || true)
    passwd_status=$(passwd -S "$user" 2>/dev/null || true)
  else
    chage_info="(chage not available)"
    passwd_status="(passwd -S not available)"
  fi

  # Sudo info
  local sudo_info
  sudo_info=$(get_sudo_info "$user")

  # SSH keys
  local ssh_info
  ssh_info=$(get_ssh_keys_info "$home")

  # Home dir checks
  local home_exists home_owner home_mode world_writable owner_root
  if [[ -d "$home" ]]; then
    home_exists=true
    home_owner=$(stat -c '%U' "$home" 2>/dev/null || echo "?")
    home_mode=$(stat -c '%a' "$home" 2>/dev/null || echo "?")
    if [[ $(stat -c '%a' "$home" 2>/dev/null) =~ [27]$ ]]; then
      world_writable=true
    else
      world_writable=false
    fi
    owner_root=false
    if [[ "$home_owner" == "root" ]]; then owner_root=true; fi
  else
    home_exists=false
    home_owner=""
    home_mode=""
    world_writable=""
    owner_root=""
  fi

  # Account locked?
  local lock_status
  if has_cmd passwd; then
    lock_status=$(passwd -S "$user" 2>/dev/null || true)
  else
    lock_status="(passwd not available)"
  fi

  # Active sessions
  local sessions
  if has_cmd who; then
    sessions=$(who | awk -v u="$user" '$1==u{print $0}' || true)
    if [[ -z "$sessions" ]]; then sessions="(no active sessions)"; fi
  else
    sessions="(who not available)"
  fi

  # Processes (top 5 by RSS)
  local procs
  procs=$(ps -u "$user" -o pid,ppid,%mem,%cpu,rss,cmd --sort=-rss 2>/dev/null | head -n 6 || true)
  if [[ -z "$procs" ]]; then procs="(no processes)"; fi

  # Failed logins
  local failed
  failed=$(get_failed_logins "$user")

  # Build output
  if $JSON; then
    # Use printf to build JSON safely (no jq dependency)
    # Escape strings simply by replacing backslashes and quotes (basic)
    esc() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e ':a;N;$!ba;s/\n/\\n/g'; }
    printf '{'
    printf '"user":"%s",' "$(esc "$username")"
    printf '"uid":%s,' "$uid"
    printf '"gid":%s,' "$gid"
    printf '"home":"%s",' "$(esc "$home")"
    printf '"shell":"%s",' "$(esc "$shell")"
    printf '"lastlog":"%s",' "$(esc "$last_login")"
    printf '"last_success":"%s",' "$(esc "$last_success")"
    printf '"passwd_status":"%s",' "$(esc "$passwd_status")"
    printf '"chage":"%s",' "$(esc "$chage_info" | tr '\n' ' ' | sed -e 's/  */ /g')"
    IFS='|' read -r sg ss <<<"$sudo_info"
    printf '"sudo_group_member":%s,' "$sg"
    printf '"sudoers_entry":%s,' "$ss"
    IFS='|' read -r keycount keymtime <<<"$ssh_info"
    printf '"ssh_authorized_keys_count":%s,' "$keycount"
    printf '"ssh_authorized_keys_mtime":"%s",' "$keymtime"
    printf '"home_exists":%s,' "$home_exists"
    printf '"home_owner":"%s",' "$home_owner"
    printf '"home_mode":"%s",' "$home_mode"
    printf '"home_world_writable":%s,' "$world_writable"
    printf '"home_owner_root":%s,' "$owner_root"
    printf '"lock_status":"%s",' "$(esc "$lock_status")"
    printf '"active_sessions":"%s",' "$(esc "$sessions")"
    printf '"processes":"%s",' "$(esc "$procs")"
    printf '"failed_logins":"%s"' "$(esc "$failed")"
    printf '}'
  else
    cat <<_EOF_
========================================
User:       $username
UID:GID:    $uid:$gid
Home:       $home
Shell:      $shell
Lastlog:    $last_login
Last login: $last_success
Password:   $passwd_status
Chage:      $chage_info
Sudo:       group_member=$(echo "$sudo_info" | cut -d'|' -f1) sudoers_entry=$(echo "$sudo_info" | cut -d'|' -f2)
SSH keys:   count=$(echo "$ssh_info" | cut -d'|' -f1) mtime=$(echo "$ssh_info" | cut -d'|' -f2)
Home dir:   exists=$home_exists owner=$home_owner mode=$home_mode world_writable=$world_writable owner_root=$owner_root
Locked:     $lock_status
Active:     $sessions
Processes:  
$procs
Failed logins:
$failed
----------------------------------------
_EOF
  fi
}

# Drive audit for all users
main() {
  local users
  users=$(get_users)

  if [[ -n "$OUTFILE" ]]; then
    exec >"$OUTFILE"
  fi

  if $JSON; then
    printf '{ "generated":"%s", "host":"%s", "users":[' "$(timestamp)" "$(hostname)"'
    first=true
    while IFS= read -r u; do
      if ! $first; then printf ','; fi
      audit_user "$u"
      first=false
    done <<<"$users"
    printf ']}\n'
  else
    echo "User audit generated: $(timestamp)"
    echo "Host: $(hostname)"
    echo
    while IFS= read -r u; do
      audit_user "$u"
    done <<<"$users"
  fi
}

main
