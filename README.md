# kerberized-nfs-lab: LDAP identity, Kerberos authentication, NFSv4 with sec=krb5p

A from-scratch Linux identity and storage lab on UTM VMs:

1. **Foundations:** authoritative DNS (BIND, forward and reverse zones) and a lab time source (chrony)
2. **Identity:** 389 Directory Server holding users and groups (rfc2307bis, memberOf), TLS from a private CA, SSSD clients
3. **Authentication:** MIT Kerberos realm `LAB.LOCAL`
4. **Storage:** NFSv4 exports secured with Kerberos (`sec=krb5`, `krb5i`, `krb5p`)

Rebuilt and extended from the earlier [linux-ldap-lab](https://github.com/OB-Adams/linux-ldap-lab).

## Hosts

| Host | IP | OS | Roles |
|---|---|---|---|
| ldap.lab.local | 192.168.0.210 | Rocky Linux 10 | BIND, chrony server, 389-ds `lab`, lab CA, KDC (phase 3) |
| client.lab.local | 192.168.0.220 | CentOS Stream 10 | SSSD client, NFS client |
| nfs.lab.local | 192.168.0.230 | Rocky Linux 10 | NFS server, SSSD client |

UTM bridged networking on 192.168.0.0/24. SELinux enforcing and firewalld on every host.

## Status

| Milestone | Status |
|---|---|
| M0 Foundations: static IPs, DNS, time | done |
| M1 Directory | done |
| M2 TLS | done |
| M3 Access control | done |
| M4 Client (SSSD) | done |
| M5 Operations: backup, restore drill | in progress |
| M6 Write-up | |
| Kerberos realm | |
| Kerberized NFS | |

## Repository layout

```
configs/dns/      named.conf options (example) and zone files
configs/chrony/   time source and client snippets
configs/389ds/    lab.inf.example
configs/tls/      CA and server certificate extension files
configs/sssd/     sssd.conf.example (client side)
ldif/             directory structure, service account, ACIs, sudo rules
scripts/          user lifecycle, health check, backup
docs/             troubleshooting.md, screenshots/
```

## Known trade-offs

- Lockout after 3 failed binds for 5 minutes stops online password guessing, but anyone who knows a username can lock that account on purpose. The short, self-expiring lockout limits that denial of service. Service accounts (`ou=Services`) are exempt through a subtree password policy and use long random passwords instead, so locking `sssd-bind` cannot take every client offline.
- The lab root CA's private key lives on ldap in `/root/ca` (mode 700). A production CA key would be kept offline.
- `lab.local` uses the mDNS-reserved `.local` TLD (RFC 6762). The VMs run no mDNS resolver, so BIND answers normally; macOS sends `.local` names to mDNS, so the Mac reaches the VMs by IP. A real deployment would use an owned domain or `home.arpa`.
- DNSSEC validation is off in BIND because the upstream network intercepts port 53 and strips DNSSEC data. See [docs/troubleshooting.md](docs/troubleshooting.md).

## Reading the login logs

When a user with the right password is refused by `simple_allow_groups`, sshd still logs `Failed password for <user>`. sshd reports any PAM failure that way. The `pam_sss(sshd:auth): authentication success` / `pam_sss(sshd:account): Access denied` pair just above it shows the real cause: authentication passed, authorization failed.

## Troubleshooting

See [docs/troubleshooting.md](docs/troubleshooting.md).
