# Ubuntu Endpoint

Monitored Linux host: Filebeat + Packetbeat + auditd, plus **DVWA** as an attack target.

## Prerequisites

- Ubuntu **22.04 LTS** or newer (24.04 also works)
- Network reachability to the ELK server on TCP **5044**
- Root / sudo
- At least 2 GB free disk (for Docker images, logs, Beat registries)

Before running the script, verify connectivity:

```bash
nc -vz <ELK_IP> 5044   # expect "Connection to <ip> 5044 port [tcp/*] succeeded!"
```

## Usage

```bash
cd endpoint-linux
chmod +x setup-ubuntu.sh
sudo ./setup-ubuntu.sh <ELK_SERVER_IP>
# example:
sudo ./setup-ubuntu.sh 10.10.10.10
```

Or via env var:

```bash
ELK_IP=10.10.10.10 sudo -E ./setup-ubuntu.sh
```

The script is idempotent — re-run it any time to re-apply configs.

## What it does

1. Installs base packages (`curl`, `auditd`, `ufw`).
2. Adds the Elastic 8.x APT repo.
3. Installs **Filebeat 8.15**, writes `/etc/filebeat/filebeat.yml` with `ELK_IP` substituted, enables the `system` and `auditd` modules.
4. Installs **Packetbeat 8.15**, writes `/etc/packetbeat/packetbeat.yml`.
5. Installs the **auditd** rules from `configs/auditd.rules` and loads them with `augenrules`.
6. Installs Docker if missing, creates `/opt/mini-soc/dvwa-logs/`, and runs **DVWA** via `dvwa/docker-compose.yml`.
7. Runs `filebeat test output` / `packetbeat test output` to confirm reachability.
8. Enables and starts both Beat services.

## Post-setup (DVWA)

1. Browse to `http://<endpoint-ip>/setup.php`.
2. Click **Create / Reset Database**.
3. Log in: `admin` / `password`.
4. Click **DVWA Security** → set to **Low** → Submit.

DVWA is now ready to receive the red-team SQLi attack.

## Verify

```bash
# Beats status
sudo systemctl status filebeat
sudo systemctl status packetbeat

# Send a test event to each output
sudo filebeat test output
sudo packetbeat test output

# Generate auditd activity so you see events in Kibana
cat /etc/passwd >/dev/null
id
```

Then in Kibana (`http://<elk-ip>:5601` → Discover → `soc-*`), filter by `fields.soc_endpoint: "ubuntu-endpoint"` — you should see events from all three sources.

## Files

| File | Purpose |
| --- | --- |
| [setup-ubuntu.sh](setup-ubuntu.sh) | Main setup script |
| [configs/filebeat.yml](configs/filebeat.yml) | Filebeat config (ships to Logstash) |
| [configs/packetbeat.yml](configs/packetbeat.yml) | Packetbeat config |
| [configs/auditd.rules](configs/auditd.rules) | Syscall/file/network audit rules |
| [dvwa/docker-compose.yml](dvwa/docker-compose.yml) | DVWA container definition |
