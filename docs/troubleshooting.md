# Troubleshooting log

Real failures hit while building this lab, with the diagnosis path for each.

| Symptom | Diagnosis | Cause / fix |
|---|---|---|
| Lab names resolve but external names return SERVFAIL; chronyd on ldap cannot resolve its NTP servers | `dig +cd` through BIND gives NOERROR; the named log shows `broken trust chain resolving 'org/DS/IN'`, first via the router and then via 1.1.1.1; `dig @1.1.1.1 +dnssec` returns no RRSIG; `dig @1.1.1.1 id.server CH TXT` times out | The upstream network intercepts port 53 and answers with a forwarder that strips DNSSEC data, so validation fails at the first DS record whatever forwarder is set. Set `dnssec-validation no` as a documented trade-off (production: encrypted DNS, DoT/DoH). Side effect fixed: chronyd on ldap resolved its time servers again and moved from stratum 10 (local clock) to an internet source. |
