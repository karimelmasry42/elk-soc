# Mini SOC — ELK Stack

A self-contained Security Operations Center lab built on the Elastic Stack, designed to detect common attacks against Linux and Windows endpoints. Developed for **Professional Training III** by a 4-person university team.

## What's in the box

- **ELK server** (Elasticsearch + Logstash + Kibana 8.15) in Docker Compose
- **Ubuntu endpoint** monitored by Filebeat, Packetbeat, and auditd, running **DVWA** (Damn Vulnerable Web Application) as an attack target
- **Windows 11 endpoint** monitored by Winlogbeat and Sysmon
- **Kali attacker scripts** — Nmap reconnaissance, Hydra SSH brute force, DVWA SQL injection, and a Windows post-exploitation simulation
- **Runbook + architecture docs** for the live demo

## Architecture

```
Attacker (Kali Linux)
    │
    ├── attacks ──► Ubuntu Endpoint (Filebeat + Packetbeat + auditd + DVWA)
    │                    │
    │                    ├── logs ──► ELK Server (Logstash → Elasticsearch → Kibana)
    │                    │
    └── attacks ──► Windows 11 Endpoint (Winlogbeat + Sysmon)
                         │
                         └── logs ──►──┘
```

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for details.

## Quick start (≤ 30 minutes)

Pick one machine to be the **ELK server** and note its IP (example: `10.10.10.10`). The same IP is passed to every endpoint.

1. **Clone the repo** on every machine:
   ```bash
   git clone <repo-url> && cd mini-soc
   ```

2. **Start the ELK server** (Ubuntu VM with Docker):
   ```bash
   cd elk-server
   sudo sysctl -w vm.max_map_count=262144
   docker compose up -d
   # Browse http://<elk-ip>:5601
   ```
   Details: [elk-server/README.md](elk-server/README.md)

3. **Set up the Ubuntu endpoint**:
   ```bash
   cd endpoint-linux
   sudo ./setup-ubuntu.sh 10.10.10.10
   ```
   Details: [endpoint-linux/README.md](endpoint-linux/README.md)

4. **Set up the Windows endpoint** (PowerShell as Administrator):
   ```powershell
   cd endpoint-windows
   .\setup-windows.ps1 -ElkIP "10.10.10.10"
   ```
   Details: [endpoint-windows/README.md](endpoint-windows/README.md)

5. **Run the attacks** from Kali:
   ```bash
   cd red-team
   bash 01-nmap-scan.sh     <ubuntu-ip>
   bash 02-hydra-bruteforce.sh <ubuntu-ip>
   bash 03-sqli-dvwa.sh     <ubuntu-ip>
   # Run 04 on the Windows endpoint itself
   ```
   Demo script: [red-team/RUNBOOK.md](red-team/RUNBOOK.md)

## Documentation

- [Architecture](docs/ARCHITECTURE.md) — components, data flow, ports
- [Network setup](docs/NETWORK-SETUP.md) — single-host, LAN, and Tailscale options
- [Troubleshooting](docs/TROUBLESHOOTING.md) — common failures and fixes

## Team

| Name | Role |
| ---- | ---- |
| TBD  | ELK server & Logstash pipelines |
| TBD  | Linux endpoint & DVWA |
| TBD  | Windows endpoint & Sysmon |
| TBD  | Red team & runbook |

## Course

Professional Training III — Mini SOC group project, 4 weeks.
