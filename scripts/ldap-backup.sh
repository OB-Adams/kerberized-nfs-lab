#!/usr/bin/env bash
# Back up the 389-ds instance: binary backup (full restore) + LDIF export
# (readable, selective restore). Keeps the newest $KEEP of each. Run as root on ldap.
set -euo pipefail

INSTANCE="${INSTANCE:-lab}"
BACKEND="${BACKEND:-userroot}"
KEEP="${KEEP:-7}"
BAKDIR="/var/lib/dirsrv/slapd-$INSTANCE/bak"
LDIFDIR="/var/lib/dirsrv/slapd-$INSTANCE/ldif"

[[ $EUID -eq 0 ]] || { echo "Run as root." >&2; exit 2; }

# Both run as server tasks over LDAPI; files are written by the dirsrv user.
dsconf "$INSTANCE" backup create
dsconf "$INSTANCE" backend export "$BACKEND"

# Retention: newest first, delete everything after the first $KEEP.
prune() { # prune <dir> <find-args...>
  local dir=$1; shift
  find "$dir" -mindepth 1 -maxdepth 1 "$@" -printf '%T@ %p\n' 2>/dev/null \
    | sort -rn | tail -n +$(( KEEP + 1 )) | cut -d' ' -f2- | xargs -r rm -rf --
}
prune "$BAKDIR" -type d
prune "$LDIFDIR" -type f -name "*${BACKEND}*.ldif"

echo "Backup complete."
echo "Newest binary backup: $(ls -1dt "$BAKDIR"/*/ 2>/dev/null | head -1)"
echo "Newest LDIF export:   $(ls -1t "$LDIFDIR"/*"${BACKEND}"*.ldif 2>/dev/null | head -1)"
