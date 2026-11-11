# Troubleshooting log

Real failures hit while building this lab, with the diagnosis path for each.

| Symptom | Diagnosis | Cause / fix |
|---|---|---|
| Lab names resolve but external names return SERVFAIL; chronyd on ldap cannot resolve its NTP servers | `dig +cd` through BIND gives NOERROR; the named log shows `broken trust chain resolving 'org/DS/IN'`, first via the router and then via 1.1.1.1; `dig @1.1.1.1 +dnssec` returns no RRSIG; `dig @1.1.1.1 id.server CH TXT` times out | The upstream network intercepts port 53 and answers with a forwarder that strips DNSSEC data, so validation fails at the first DS record whatever forwarder is set. Set `dnssec-validation no` as a documented trade-off (production: encrypted DNS, DoT/DoH). Side effect fixed: chronyd on ldap resolved its time servers again and moved from stratum 10 (local clock) to an internet source. |
| SSSD on client stays `Offline`; `id kofi` says no such user | `sssctl debug-level 6`; `sssd_lab.local.log` shows `Password Policy Response: ... error [Account locked]` and `Bind result: Constraint violation(19), Exceed password retry limit` for sssd-bind (the "Failed to resolve server ... no data" lines after it were AAAA lookups during failover, not the cause) | A wrong password in `sssd.conf` made SSSD fail three binds, so the global lockout policy locked the service account; while locked even the correct password is refused. Design flaw: anyone could lock sssd-bind and take every client offline. Fix: subtree password policy on `ou=Services` with lockout off (`nsslapd-pwpolicy-local=on`, `dsconf lab localpwp addsubtree ou=Services,dc=lab,dc=local --pwdlockout off`), a 32-character random password for sssd-bind, and `lookup_family_order = ipv4_only` in sssd.conf. |

## LDAP result codes seen in this lab

| Code | Name | Meaning here |
|---|---|---|
| 13 | Confidentiality required | password bind attempted without TLS: `Operation requires a secure connection` (`nsslapd-require-secure-binds=on`) |
| 19 | Constraint violation | account locked by password policy: `Exceed password retry limit. Please try later.` |
| 32 | No such object | base DN does not exist (or instance has no backend) |
| 48 | Inappropriate authentication | anonymous search outside the rootDSE: `Anonymous access is not allowed.` (`nsslapd-allow-anonymous-access=rootdse`) |
| 49 | Invalid credentials | wrong password or wrong bind DN |
| 53 | Unwilling to perform | bind with a DN but an empty password (unauthenticated bind) |
| 65 | Object class violation | entry breaks the schema (e.g. two structural classes) |
| 68 | Already exists | entry or config object (e.g. an index) already present |
