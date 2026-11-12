#!/usr/bin/env bash
# Delete a user and remove their member references from every group.
# Usage: ldap-del-user.sh <username>
# Refuses if the user is the last member of a group: groupOfNames requires
# at least one member, so the group would become invalid.
set -euo pipefail

LDAP_URI="${LDAP_URI:-ldap://ldap.lab.local}"
BASE_DN="${BASE_DN:-dc=lab,dc=local}"
ADMIN_DN="${ADMIN_DN:-cn=Directory Manager}"

[[ $# -eq 1 ]] || { echo "Usage: $0 <username>" >&2; exit 2; }
user=$1
[[ $user =~ ^[a-z][a-z0-9_-]{1,31}$ ]] || { echo "Invalid username: $user" >&2; exit 2; }

pwfile=$(mktemp); chmod 600 "$pwfile"; trap 'rm -f "$pwfile"' EXIT
read -r -s -p "Directory Manager password: " adminpw; echo >&2
printf '%s' "$adminpw" > "$pwfile"; unset adminpw

ldap()    { local tool=$1; shift; "$tool" -x -ZZ -H "$LDAP_URI" -D "$ADMIN_DN" -y "$pwfile" "$@"; }
lsearch() { ldap ldapsearch -LLL -o ldif-wrap=no "$@"; }

user_dn="uid=$user,ou=People,$BASE_DN"
lsearch -b "$user_dn" -s base dn | grep -q '^dn:' || { echo "No such user: $user" >&2; exit 1; }

mapfile -t groups < <(lsearch -b "ou=Groups,$BASE_DN" "(member=$user_dn)" dn | sed -n 's/^dn: //p')

# Pre-check every group before changing anything.
for gdn in "${groups[@]}"; do
  n=$(lsearch -b "$gdn" -s base member | grep -c '^member:' || true)
  if (( n <= 1 )); then
    echo "Refusing: $user is the only member of $gdn (groupOfNames needs a member)." >&2
    exit 1
  fi
done

echo "User: $user_dn"
echo "Groups: ${groups[*]:-none}"
read -r -p "Delete $user and remove from these groups? [y/N] " ans
[[ $ans == [yY] ]] || { echo "Aborted."; exit 1; }

for gdn in "${groups[@]}"; do
  ldap ldapmodify <<LDIF
dn: $gdn
changetype: modify
delete: member
member: $user_dn
LDIF
done

ldap ldapdelete "$user_dn"
echo "Deleted $user. On SSSD clients, run: sss_cache -E"
