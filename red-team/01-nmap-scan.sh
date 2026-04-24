#!/bin/bash
# Mini SOC — Red team attack #1: Nmap reconnaissance.
#
# Demonstrates a TCP SYN scan of the first 1000 ports. Expected to light up:
#   • Packetbeat flow records (many short TCP flows from attacker IP)
#   • Packetbeat "connection refused" / "TCP RST" signals on closed ports
#   • auditd network rule events if scanning from the local host
#
# Usage:  bash 01-nmap-scan.sh <target-ip>

set -euo pipefail

TARGET="${1:-}"

if [[ -z "${TARGET}" ]]; then
  cat <<EOF >&2
Usage: $0 <target-ip>
Example: $0 10.10.10.20

This runs:  nmap -sS -p 1-1000 -T4 <target>
  -sS          TCP SYN (half-open) scan — faster & stealthier than full connect
  -p 1-1000    scan first 1000 ports only (keeps demo time reasonable)
  -T4          aggressive timing — fast but noisy, good for triggering detections
EOF
  exit 1
fi

if ! command -v nmap >/dev/null 2>&1; then
  echo "❌ nmap not installed. On Kali: already present. Elsewhere: sudo apt install nmap" >&2
  exit 1
fi

cat <<BANNER

╔══════════════════════════════════════════════════════════════════╗
║  ATTACK 1 — Nmap SYN scan                                        ║
║  Target : ${TARGET}
║  Scan   : -sS -p 1-1000 -T4                                      ║
╚══════════════════════════════════════════════════════════════════╝

What to look for in Kibana:
  Index : soc-packetbeat-*
  Field : source.ip = <this attacker IP>
  Expect: dozens of short flows in the same second, many with flags.syn
          and no flags.ack (half-open) to varying destination.port values.

Press Ctrl+C to abort.
BANNER

sudo nmap -sS -p 1-1000 -T4 "${TARGET}"

echo
echo "✓ Scan complete. Check Kibana → Discover → soc-packetbeat-* for a burst"
echo "  of flow records with source.ip=<attacker> and many distinct destination.port."
