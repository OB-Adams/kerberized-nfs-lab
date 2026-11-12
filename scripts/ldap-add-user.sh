#!/usr/bin/env bash
# Add a POSIX user (rfc2307bis) and set an initial password.
# Usage: ldap-add-user.sh <username> <given-name> <surname> [extra-group ...]
# The user gets gidNumber of the primary group (default ldapusers) and is added
# as a member of it and of any extra groups. Run where openldap-clients is
# installed and the lab CA is trusted.
set -euo pipefail

LDAP_URI="${LDAP_URI:-ldap://ldap.lab.local}"
BASE_DN="${BASE_DN:-dc=lab,dc=local}"
ADMIN_DN="${ADMIN_DN:-cn=Directory Manager}"
PRIMARY_GROUP="${PRIMARY_GROUP:-ldapusers}"
UID_FLOOR="${UID_FLOOR:-10000}"

usage() { echo "Usage: $0 <username> <given-name> <surname> [extra-group ...]" >&2; exit 2; }
[[ $# -ge 3 ]] || usage
user=$1 given=$2 sn=$3; shift 3
extra_groups=("$@")
[[ $user =~ ^[a-z][a-z0-9_-]{1,31}$ ]] || { echo "Invalid username: $user" >&2; exit 2; }

# Admin password goes in a 0600 temp file read with -y, never on the command line.
pwfile=$(mktemp); chmod 600 "$pwfile"; trap 'rm -f "$pwfile"' EXIT
read -r -s -p "Directory Manager password: " adminpw; echo >&2
printf '%s' "$adminpw" > "$pwfile"; unset adminpw

ldap()    { local tool=$1; shift; "$tool" -x -ZZ -H "$LDAP_URI" -D "$ADMIN_DN" -y "$pwfile" "$@"; }
lsearch() { ldap ldapsearch -LLL -o ldif-wrap=no "$@"; }
group_dn() { lsearch -b "ou=Groups,$BASE_DN" "(&(objectClass=posixGroup)(cn=$1))" dn | sed -n 's/^dn: //p'; }

user_dn="uid=$user,ou=People,$BASE_DN"
if lsearch -b "ou=People,$BASE_DN" "(uid=$user)" dn | grep -q '^dn:'; then
  echo "User '$user' already exists." >&2; exit 1
fi

# Resolve every group before writing anything, so a typo aborts cleanly.
primary_dn=$(group_dn "$PRIMARY_GROUP")
[[ -n $primary_dn ]] || { echo "Primary group '$PRIMARY_GROUP' not found." >&2; exit 1; }
gid=$(lsearch -b "$primary_dn" -s base gidNumber | awk '/^gidNumber:/{print $2}')
member_of=("$primary_dn")
for g in "${extra_groups[@]}"; do
  d=$(group_dn "$g"); [[ -n $d ]] || { echo "Group '$g' not found." >&2; exit 1; }
  member_of+=("$d")
done

# Next free uidNumber: highest existing + 1, never at or below the floor.
max=$(lsearch -b "ou=People,$BASE_DN" "(uidNumber=*)" uidNumber | awk '/^uidNumber:/{print $2}' | sort -n | tail -1)
next=$(( ${max:-$UID_FLOOR} + 1 ))
(( next > UID_FLOOR )) || next=$(( UID_FLOOR + 1 ))

ldap ldapadd <<LDIF
dn: $user_dn
objectClass: top
objectClass: person
objectClass: organizationalPerson
objectClass: inetOrgPerson
objectClass: posixAccount
uid: $user
cn: $given $sn
sn: $sn
givenName: $given
uidNumber: $next
gidNumber: $gid
homeDirectory: /home/$user
loginShell: /bin/bash
LDIF

# Group membership by DN; the memberOf plugin writes the reverse link.
for gdn in "${member_of[@]}"; do
  ldap ldapmodify <<LDIF
dn: $gdn
changetype: modify
add: member
member: $user_dn
LDIF
done

echo "Created $user (uidNumber $next, gidNumber $gid). Set the initial password:"
ldap ldappasswd -S "$user_dn"
