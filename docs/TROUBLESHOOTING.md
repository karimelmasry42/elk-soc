# Troubleshooting

## Elasticsearch won't start

**Symptom:** `elasticsearch` container exits immediately or logs `max virtual memory areas vm.max_map_count [65530] is too low`.

**Fix:**
```bash
sudo sysctl -w vm.max_map_count=262144
# Persist across reboots:
echo "vm.max_map_count=262144" | sudo tee /etc/sysctl.d/99-elasticsearch.conf
```

On macOS, run Docker Desktop → Settings → Resources and allocate ≥ 6 GB RAM. The Linux VM inside Docker Desktop handles `vm.max_map_count` automatically in recent versions; if not, use `docker run --privileged --rm tianon/true sysctl -w vm.max_map_count=262144`.

**Other causes:**
- Container OOM-killed: raise `ES_JAVA_OPTS` in `elk-server/.env` (default is 2 GB heap; needs ~3 GB container memory).
- Volume permission errors: `docker compose down -v` to wipe the `esdata` volume and restart.

## Beats can't connect to Logstash

**Symptom:** `*beat test output` fails with `dial tcp ...:5044: connect: connection refused` or `i/o timeout`.

**Checks, in order:**
1. Is the ELK server up? `curl http://<ELK_IP>:9200` → should return cluster info.
2. Is port 5044 open? From the endpoint: `nc -vz <ELK_IP> 5044`.
3. Is Logstash listening? On the ELK host: `docker compose logs logstash | grep 5044` — look for `Starting server on port: 5044`.
4. Firewall: on Ubuntu `sudo ufw status`; on Windows `Get-NetFirewallRule -DisplayName "*Beats*"`. Allow outbound 5044 on endpoints.
5. Wrong IP: every endpoint config has `ELK_IP` replaced by `sed`. Verify with `grep -r <ELK_IP> /etc/filebeat/ /etc/packetbeat/`.

## No data in Kibana

**Symptom:** Kibana Data View shows zero hits.

**Checks:**
1. Index exists? `curl http://<ELK_IP>:9200/_cat/indices/soc-*?v` — should list `soc-system-*`, etc.
2. Time range: Kibana defaults to "Last 15 minutes". Widen to "Last 24 hours" in the top-right.
3. Data View pattern: should be `soc-*`, not `soc-` (without wildcard).
4. Logstash errors: `docker compose logs -f logstash` — look for `_grokparsefailure` or exceptions.
5. Beat sending: on endpoint, `tail -f /var/log/filebeat/filebeat` (Linux) or `Get-Content -Wait C:\ProgramData\winlogbeat\logs\winlogbeat` (Windows) for `published X events`.

## DVWA shows a blank page or "Unable to connect to database"

**Fix:** The database isn't initialized. Browse to `http://<dvwa-ip>/setup.php` → click **Create / Reset Database** → log in with `admin` / `password`. Then set DVWA Security → **Low**.

## Sysmon not logging

**Symptom:** `Get-WinEvent -LogName Microsoft-Windows-Sysmon/Operational` returns nothing.

**Checks:**
1. Is the service running? `Get-Service sysmon64` — should be `Running`.
2. Is the config applied? `Sysmon64.exe -c` → prints active config; should match `sysmonconfig.xml`.
3. Re-apply config: `Sysmon64.exe -c C:\path\to\sysmonconfig.xml`.
4. Full reinstall: `Sysmon64.exe -u force; Sysmon64.exe -accepteula -i C:\path\to\sysmonconfig.xml`.

## Docker Compose version mismatch

**Symptom:** `docker-compose: command not found` or `Unsupported config option`.

**Fix:** Use the **v2** CLI (`docker compose`, two words) — it ships with Docker Desktop and recent `docker-ce` on Linux. The legacy v1 `docker-compose` (Python) is unsupported by this project. If `docker compose version` fails, install the plugin:

```bash
# Ubuntu 22.04+
sudo apt install docker-compose-plugin
```

## Winlogbeat fails to start as a service

**Symptom:** `Start-Service winlogbeat` returns `Service cannot be started`.

**Fix:**
- Check the config: `.\winlogbeat.exe test config -c winlogbeat.yml`.
- Check output: `.\winlogbeat.exe test output -c winlogbeat.yml`.
- View service log: `Get-EventLog -LogName Application -Source winlogbeat -Newest 20`.
- Reinstall service: `Stop-Service winlogbeat; .\install-service-winlogbeat.ps1`.

## Filebeat reports "Connection to backoff"

**Symptom:** Logstash log shows `Received tag event but elasticsearch is unreachable`.

**Fix:** Elasticsearch is down or Logstash can't reach it inside the Docker network. Restart just the ES container: `docker compose restart elasticsearch`, wait 30 s, then `docker compose restart logstash`.

## Everything works but red-team scripts produce no Kibana events

**Checks:**
- The attack is reaching the endpoint (check with `tcpdump` on the endpoint).
- The endpoint's log file actually records the event. For SSH failures: `grep "Failed password" /var/log/auth.log`. For DVWA: `tail /var/log/apache2/access.log` (or the host-mounted `dvwa-logs/`).
- Time skew between endpoint and ELK server — run `timedatectl status` / `w32tm /query /status`; Kibana filters by `@timestamp`, and a 5-minute skew hides the event.
