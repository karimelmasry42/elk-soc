# Demo Runbook

A 15-minute live demonstration of the Mini SOC. Every step lists **what to run**, **where to click in Kibana**, and a **suggested line of narration**.

Assumes the ELK server, Ubuntu endpoint, Windows endpoint, and Kali attacker are all up and reachable. Replace IPs as needed.

| Placeholder | Meaning |
| --- | --- |
| `<ELK_IP>` | IP of the ELK server, e.g. `10.10.10.10` |
| `<UBUNTU_IP>` | IP of the Ubuntu endpoint, e.g. `10.10.10.20` |
| `<WIN_IP>` | IP of the Windows endpoint, e.g. `10.10.10.30` |

---

## 0 · Setup (before the audience arrives) — 5 min

- Kibana open in one browser tab at `http://<ELK_IP>:5601/app/discover`
- Data view `soc-*` selected, time range **Last 15 minutes**, auto-refresh **5 s**
- Second tab: `http://<UBUNTU_IP>/` (DVWA login page) for the SQLi demo
- Three terminals ready on Kali, each in `mini-soc/red-team/`
- One PowerShell (Admin) open on the Windows endpoint at `mini-soc/red-team/`

**Sanity check (2 min):** run `ssh testuser@<UBUNTU_IP>` (wrong password) and confirm a `Failed password` event appears in Kibana within ~10 s. If it does not, see [docs/TROUBLESHOOTING.md](../docs/TROUBLESHOOTING.md) before starting.

---

## 1 · Introduction — 1 min

**Show:** the architecture diagram from [docs/ARCHITECTURE.md](../docs/ARCHITECTURE.md).

> "We built a Mini SOC on the Elastic Stack. Three machines send telemetry to a central Logstash pipeline: an Ubuntu server running a vulnerable web app, a Windows 11 workstation, and a Kali attacker. Every event is parsed, tagged, and routed to an index you can search in Kibana."

---

## 2 · Attack 1 — Nmap reconnaissance — 2 min

**Terminal (Kali):**

```bash
bash 01-nmap-scan.sh <UBUNTU_IP>
```

**In Kibana while it runs:**
- Index: `soc-packetbeat-*`
- Filter: `source.ip : "<KALI_IP>"`
- Visualize → "Top values of `destination.port`" bar chart

> "Watch the bar chart fill with dozens of destination ports from the same source IP in seconds. That's the signature of a port scan — a legitimate user never hits 1000 ports in 30 seconds."

**Screenshot placeholder:** bar chart with ~15 bars, each < 5 events, within a single minute.

**Fallback if nothing appears:** switch to `soc-system-*` and show that the Ubuntu endpoint's `/var/log/syslog` recorded the scan via the kernel. Or check `docker compose logs logstash` for grok failures.

---

## 3 · Attack 2 — SSH brute force — 3 min

**Terminal (Kali):**

```bash
bash 02-hydra-bruteforce.sh <UBUNTU_IP>
```

**In Kibana:**
- Index: `soc-system-*`
- Filter: `tags : "soc.auth.failed"`
- Add columns: `source.ip`, `user.name`, `message`
- Switch to **Lens** → create a time-series of `count()` grouped by `source.ip`

> "Twenty password attempts in under five seconds, all from one IP, all for the root user. This is a classic brute-force signature. If we had detection rules on, this would page the on-call analyst."

**Screenshot placeholder:** Lens chart showing a spike of ~20 auth failures at a single timestamp.

**Fallback:** run the hydra command with `-V` so you can point at the terminal output while Kibana catches up.

---

## 4 · Attack 3 — SQL injection against DVWA — 3 min

**Preflight:**

- Browse to `http://<UBUNTU_IP>/` → confirm DVWA is initialized and Security = Low.
- In Kibana, open a saved search on `soc-dvwa-*`.

**Terminal (Kali):**

```bash
bash 03-sqli-dvwa.sh <UBUNTU_IP>
```

**In Kibana:**
- Index: `soc-dvwa-*`
- Filter: `tags : "soc.attack.web"`
- Expand the top event; highlight `url.original` containing `UNION SELECT` / `OR '1'='1` / `<script>`
- Highlight `soc.severity : "critical"` assigned by the Logstash pipeline

> "Logstash ran a regex over the Apache access log and automatically tagged three requests as web attacks. Notice how we didn't write a detection rule per payload — the pipeline catches the pattern."

**Screenshot placeholder:** Discover row expanded, with the `url.original` field highlighted.

**Fallback:** `ssh` into the Ubuntu endpoint and `tail /opt/mini-soc/dvwa-logs/access.log` to show the raw log line, then explain the Logstash grok.

---

## 5 · Attack 4 — Windows post-exploitation — 4 min

**PowerShell (Windows endpoint, Admin):**

```powershell
.\04-windows-suspicious.ps1
```

**In Kibana:**
- Index: `soc-winlogbeat-*`
- Filter: `fields.soc_endpoint : "windows-endpoint"`
- Split the time window:
  1. `winlog.event_id : 1`  → Sysmon process creates: `whoami.exe`, `net.exe`, `powershell.exe`
  2. `winlog.event_id : 11` → FileCreate `eicar.txt`
  3. `winlog.event_id : 13` → Registry change under `Schedule\TaskCache`
  4. Switch channel filter to `Security`, show `event_id : 4688` and `4698/4699`

> "Sysmon gives us deep visibility. We see the EICAR file being dropped, a scheduled task registered and removed — classic persistence pattern — and an encoded PowerShell command, which attackers love because it hides intent. All four techniques are in the MITRE ATT&CK matrix."

**Screenshot placeholder:** Discover view with four filters pinned, each producing 1-3 events.

**Fallback:** if events are delayed, open PowerShell on the endpoint and run `Get-WinEvent -LogName 'Microsoft-Windows-Sysmon/Operational' -MaxEvents 10` to show the raw events locally.

---

## 6 · Wrap-up — 1 min

**Show:** a single Kibana Dashboard panel (or just Discover) filtered to the last 10 minutes, grouped by `fields.soc_endpoint`. Highlight that three endpoints contributed events from four different attack categories.

> "In 15 minutes we demonstrated reconnaissance, credential attack, web attack, and post-exploitation — all detected by the same pipeline, indexed by source, severity-tagged, and searchable. Extending this to alerting, retention, or a real enterprise is an incremental step from here."

---

## Resetting between runs

```bash
# On Kali — nothing to reset.

# On the Ubuntu endpoint — clear old auth failures so the next hydra run is obvious:
sudo truncate -s 0 /var/log/auth.log

# On the ELK server — optional: delete the day's indices for a clean slate.
curl -X DELETE "http://<ELK_IP>:9200/soc-*"
```

## Time budget

| Section | Target |
| --- | ---: |
| 0 · Setup | 5 min (before) |
| 1 · Intro | 1 min |
| 2 · Nmap | 2 min |
| 3 · Hydra | 3 min |
| 4 · SQLi | 3 min |
| 5 · Windows | 4 min |
| 6 · Wrap | 1 min |
| **Live total** | **14 min** |
