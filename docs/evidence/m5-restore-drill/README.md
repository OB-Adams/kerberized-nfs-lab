# M5 restore drill (2026-11-12)

Full restore of the 389-ds instance from a binary backup after a user was deleted.
Both hosts ran each step through a `run()` wrapper that timestamps commands into
`session-ldap.log` and `session-client.log`. Clocks were synchronised by chrony
(`makestep 1.0 -1`, see docs/troubleshooting.md), so the two logs interleave by time.

| Time | Host | Step | Result |
|---|---|---|---|
| 01:58:23 | ldap | baseline | ama present, uidNumber 10002, memberOf ldapusers; ldapusers lists kofi, ama, yaw |
| 01:58:35 | ldap | `ldap-backup.sh` | `bak/backup-2026_11_12_01_58_36/` and `ldif/lab-userroot-2026_11_12_01_58_38.ldif` |
| 01:58:41 | ldap | incident: `ldap-del-user.sh ama` | member value removed from ldapusers, entry deleted |
| 01:58:47 | ldap | search for ama | no entries |
| 01:58:59 | client | `sss_cache -E`, `id ama` | no such user |
| 01:59:04 | ldap | `dsctl lab stop` | stopped |
| 01:59:05 | ldap | `dsctl lab bak2db backup-2026_11_12_01_58_36` | bak2db successful |
| 01:59:06 | ldap | `dsctl lab start` | started |
| 01:59:13 | ldap | verify | ama back: uidNumber 10002, memberOf ldapusers; ldapusers lists kofi, ama, yaw |
| 01:59:21 | client | verify over StartTLS | same entry and membership |
| 01:59:31 | client | `sss_cache -E`, `id ama` | `uid=10002(ama) gid=10000(ldapusers)` |

- Outage (stop to start): 2 seconds. The restore returns the whole database to 01:58:36; changes after that point would be lost (RPO = time since last backup).
- memberOf on the user and member on the group come back together because both are stored in the backup.
- Screenshot 15 (`docs/screenshots/15-backup-restore.png`) shows the client side of a repeat run immediately after the logged one, including SSSD answering for the deleted user from its cache until `sss_cache -E`.
