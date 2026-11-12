#!/usr/bin/env bash
# Health check for the LDAP service. Safe for cron, a systemd timer or monitoring.
# Exit codes (Nagios convention): 0 OK, 1 WARNING, 2 CRITICAL.
# Uses the system trust store, so the lab CA must be installed on the host running it.
set -uo pipefail

HOST="${LDAP_HOST:-ldap.lab.local}"
BASE_DN="${BASE_DN:-dc=lab,dc=local}"
WARN_DAYS="${WARN_DAYS:-30}"
status=0
ok()   { echo "OK: $1"; }
warn() { echo "WARNING: $1"; (( status < 1 )) && status=1; }
crit() { echo "CRITICAL: $1"; status=2; }

# 1. Ports reachable (3 s timeout each)
for port in 389 636; do
  if timeout 3 bash -c "exec 3<>/dev/tcp/$HOST/$port" 2>/dev/null; then
    ok "port $port reachable"
  else
    crit "port $port unreachable on $HOST"
  fi
done

# 2. StartTLS with certificate verification, and the suffix is served
if out=$(ldapsearch -x -ZZ -H "ldap://$HOST" -LLL -s base -b "" namingContexts 2>&1); then
  if grep -qi "^namingContexts: $BASE_DN$" <<<"$out"; then
    ok "StartTLS rootDSE query succeeded, serving $BASE_DN"
  else
    crit "server does not list $BASE_DN in namingContexts"
  fi
else
  crit "StartTLS rootDSE query failed: $(head -1 <<<"$out")"
fi

# 3. LDAPS certificate: chain + hostname verification, then lifetime
tls=$(openssl s_client -connect "$HOST:636" -servername "$HOST" -verify_hostname "$HOST" </dev/null 2>&1)
code=$(sed -n 's/.*Verify return code: \([0-9]*\).*/\1/p' <<<"$tls" | tail -1)
cert=$(openssl x509 <<<"$tls" 2>/dev/null)
if [[ -z $cert ]]; then
  crit "could not read certificate from $HOST:636"
elif [[ $code != 0 ]]; then
  crit "certificate verification failed (verify return code ${code:-unknown})"
elif ! openssl x509 -noout -checkend 0 <<<"$cert" >/dev/null; then
  crit "certificate has expired"
elif ! openssl x509 -noout -checkend $(( WARN_DAYS * 86400 )) <<<"$cert" >/dev/null; then
  warn "certificate expires within $WARN_DAYS days ($(openssl x509 -noout -enddate <<<"$cert" | cut -d= -f2))"
else
  ok "certificate verified for $HOST, valid until $(openssl x509 -noout -enddate <<<"$cert" | cut -d= -f2)"
fi

exit $status
