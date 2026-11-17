#!/bin/bash
# Run as root on nfs.lab.local: the shared directory for group projects.
# setgid puts new files in group projects; the default ACL makes them group-writable
# whatever the creator's umask (NFSv4.2 sends the umask separately, so this also
# applies to files created over NFS).
set -euo pipefail
mkdir -p /srv/nfs/projects
chown root:projects /srv/nfs/projects
chmod 2770 /srv/nfs/projects
setfacl -m d:g:projects:rwX,d:o::--- /srv/nfs/projects
getfacl /srv/nfs/projects
