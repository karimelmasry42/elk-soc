#!/bin/bash
# Mini SOC — Ubuntu endpoint setup.
# Installs and configures Filebeat, Packetbeat, auditd, and DVWA.
# Idempotent: safe to run multiple times.
#
# Usage:  sudo ./setup-ubuntu.sh <ELK_SERVER_IP>
# Or:     ELK_IP=10.10.10.10 sudo -E ./setup-ubuntu.sh

set -euo pipefail

# -----------------------------------------------------------------------------
# Arguments
# -----------------------------------------------------------------------------
ELK_IP="${1:-${ELK_IP:-}}"

if [[ -z "${ELK_IP}" ]]; then
  cat <<EOF >&2
Usage: sudo $0 <ELK_SERVER_IP>
   or: ELK_IP=<ip> sudo -E $0

Example: sudo $0 10.10.10.10
EOF
  exit 1
fi

if [[ "$(id -u)" -ne 0 ]]; then
  echo "❌ Must be run as root (use sudo)." >&2
  exit 1
fi

ELASTIC_VERSION="8.15.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DVWA_LOG_DIR="/opt/mini-soc/dvwa-logs"

say()  { printf '\n\033[1;36m▶ %s\033[0m\n' "$*"; }
warn() { printf '\n\033[1;33m⚠ %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m  ✓ %s\033[0m\n' "$*"; }

# -----------------------------------------------------------------------------
# 1) OS prep
# -----------------------------------------------------------------------------
say "Updating apt and installing base packages"
apt-get update -qq
apt-get install -y -qq \
  curl gnupg apt-transport-https ca-certificates \
  auditd audispd-plugins \
  ufw \
  >/dev/null
ok "Base packages installed"

# -----------------------------------------------------------------------------
# 2) Elastic APT repo (idempotent)
# -----------------------------------------------------------------------------
say "Configuring Elastic ${ELASTIC_VERSION} APT repository"
if [[ ! -f /usr/share/keyrings/elastic-archive-keyring.gpg ]]; then
  curl -fsSL https://artifacts.elastic.co/GPG-KEY-elasticsearch \
    | gpg --dearmor -o /usr/share/keyrings/elastic-archive-keyring.gpg
fi
cat >/etc/apt/sources.list.d/elastic-8.x.list <<EOF
deb [signed-by=/usr/share/keyrings/elastic-archive-keyring.gpg] https://artifacts.elastic.co/packages/8.x/apt stable main
EOF
apt-get update -qq
ok "Elastic repo configured"

# -----------------------------------------------------------------------------
# 3) Filebeat
# -----------------------------------------------------------------------------
say "Installing Filebeat ${ELASTIC_VERSION}"
apt-get install -y -qq "filebeat=${ELASTIC_VERSION}" >/dev/null || apt-get install -y -qq filebeat >/dev/null
ok "Filebeat installed"

say "Writing /etc/filebeat/filebeat.yml"
install -m 0600 "${SCRIPT_DIR}/configs/filebeat.yml" /etc/filebeat/filebeat.yml
sed -i "s/ELK_IP/${ELK_IP}/g" /etc/filebeat/filebeat.yml
ok "filebeat.yml in place (ELK_IP=${ELK_IP})"

say "Enabling Filebeat modules: system, auditd"
filebeat modules enable system auditd >/dev/null
ok "Modules enabled"

# -----------------------------------------------------------------------------
# 4) Packetbeat
# -----------------------------------------------------------------------------
say "Installing Packetbeat ${ELASTIC_VERSION}"
apt-get install -y -qq "packetbeat=${ELASTIC_VERSION}" >/dev/null || apt-get install -y -qq packetbeat >/dev/null
ok "Packetbeat installed"

say "Writing /etc/packetbeat/packetbeat.yml"
install -m 0600 "${SCRIPT_DIR}/configs/packetbeat.yml" /etc/packetbeat/packetbeat.yml
sed -i "s/ELK_IP/${ELK_IP}/g" /etc/packetbeat/packetbeat.yml
ok "packetbeat.yml in place"

# -----------------------------------------------------------------------------
# 5) auditd rules
# -----------------------------------------------------------------------------
say "Installing auditd rules"
install -m 0640 "${SCRIPT_DIR}/configs/auditd.rules" /etc/audit/rules.d/mini-soc.rules
augenrules --load >/dev/null
systemctl enable --now auditd >/dev/null
ok "auditd rules loaded"

# -----------------------------------------------------------------------------
# 6) Docker + DVWA
# -----------------------------------------------------------------------------
if ! command -v docker >/dev/null 2>&1; then
  say "Installing Docker"
  apt-get install -y -qq docker.io docker-compose-plugin >/dev/null
  systemctl enable --now docker >/dev/null
  ok "Docker installed"
else
  ok "Docker already installed"
fi

say "Preparing DVWA log directory at ${DVWA_LOG_DIR}"
mkdir -p "${DVWA_LOG_DIR}"
# Apache inside the container runs as uid 33 (www-data). Give it write + let root/filebeat read.
chown 33:33 "${DVWA_LOG_DIR}"
chmod 0755  "${DVWA_LOG_DIR}"
ok "Log dir ready"

say "Starting DVWA container"
(cd "${SCRIPT_DIR}/dvwa" && docker compose up -d)
ok "DVWA started on port 80 — http://<this-host>/setup.php to init DB"

# -----------------------------------------------------------------------------
# 7) Test outputs and enable services
# -----------------------------------------------------------------------------
say "Testing Filebeat → Logstash connectivity"
if filebeat test output; then
  ok "Filebeat can reach ${ELK_IP}:5044"
else
  warn "Filebeat cannot reach ${ELK_IP}:5044 — check ELK is up and firewall"
fi

say "Testing Packetbeat → Logstash connectivity"
if packetbeat test output; then
  ok "Packetbeat can reach ${ELK_IP}:5044"
else
  warn "Packetbeat cannot reach ${ELK_IP}:5044 — check ELK is up and firewall"
fi

say "Enabling and starting Filebeat + Packetbeat services"
systemctl enable --now filebeat >/dev/null
systemctl enable --now packetbeat >/dev/null
ok "Services running"

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
cat <<SUMMARY

────────────────────────────────────────────────────────────────────
Ubuntu endpoint configured.
  ELK server     : ${ELK_IP}:5044
  Filebeat       : system + auditd modules + DVWA access log
  Packetbeat     : DNS, HTTP, TLS, flows on 'any'
  auditd         : execve, sensitive files, network, auth
  DVWA           : http://<this-host>/  (init at /setup.php)

Next:
  1. Browse to http://<this-host>/setup.php → Create / Reset Database
  2. Login as admin/password → DVWA Security → Low
  3. In Kibana (http://${ELK_IP}:5601), create Data View 'soc-*'
────────────────────────────────────────────────────────────────────
SUMMARY
