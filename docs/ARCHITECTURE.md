# Architecture

## Diagram

```
┌─────────────────────────┐                ┌──────────────────────────────────┐
│  Kali Linux (Attacker)  │                │        ELK Server (Ubuntu)       │
│                         │                │                                  │
│  • Nmap                 │                │   Docker Compose:                │
│  • Hydra                │                │   ┌──────────────────────────┐   │
│  • curl (SQLi/XSS)      │                │   │ Logstash   :5044 (beats) │   │
│                         │                │   ├──────────────────────────┤   │
└──────────┬──────────────┘                │   │ Elasticsearch  :9200     │   │
           │                               │   ├──────────────────────────┤   │
   attacks │                               │   │ Kibana         :5601     │   │
           │                               │   └──────────────────────────┘   │
           ▼                               └──────────────▲───────────────────┘
┌─────────────────────────┐                               │
│  Ubuntu Endpoint        │   ── Filebeat/Packetbeat ────┤ :5044
│  • Filebeat (system,    │                               │
│    auditd, DVWA access) │                               │
│  • Packetbeat           │                               │
│  • auditd               │                               │
│  • DVWA (Docker :80)    │                               │
└─────────────────────────┘                               │
                                                          │
┌─────────────────────────┐                               │
│  Windows 11 Endpoint    │   ── Winlogbeat ─────────────┤ :5044
│  • Winlogbeat           │                               │
│  • Sysmon               │                               │
└─────────────────────────┘                               │
```

## Components

| Component | Role | Version |
| --- | --- | --- |
| Elasticsearch | Document store, indexes `soc-*` | 8.15.0 |
| Logstash | Parses/enriches Beat events, routes to indices | 8.15.0 |
| Kibana | Visualization, dashboards, detection rules | 8.15.0 |
| Filebeat | System logs, auditd, DVWA Apache access log | 8.15.0 |
| Packetbeat | Network flows, DNS, HTTP, TLS on Ubuntu endpoint | 8.15.0 |
| Winlogbeat | Windows event logs + Sysmon channel | 8.15.0 |
| Sysmon | Deep process/network/file/registry telemetry on Windows | 15.x |
| auditd | Syscall, file, and network auditing on Linux | distro |
| DVWA | Intentionally vulnerable web app (target) | `vulnerables/web-dvwa` |

## Data flow

```
  event on endpoint
        │
        ▼
  Beat (Filebeat/Packetbeat/Winlogbeat)
        │  TCP/5044  (Lumberjack, plain — lab only)
        ▼
  Logstash pipeline
        ├── beats-input.conf   (input → port 5044)
        ├── filters.conf       (tag, grok, enrich, set [@metadata][soc_type])
        └── elasticsearch-output.conf  (→ index soc-<type>-YYYY.MM.dd)
        │
        ▼
  Elasticsearch  (single-node, xpack security disabled)
        │
        ▼
  Kibana   (Data View: soc-*)
```

## Logstash tagging & routing

`filters.conf` sets `[@metadata][soc_type]` based on the source:

| Source | `soc_type` | Index |
| --- | --- | --- |
| Filebeat — system module | `system` | `soc-system-YYYY.MM.dd` |
| Filebeat — auditd module | `auditd` | `soc-auditd-YYYY.MM.dd` |
| Filebeat — DVWA access log input | `dvwa` | `soc-dvwa-YYYY.MM.dd` |
| Packetbeat | `packetbeat` | `soc-packetbeat-YYYY.MM.dd` |
| Winlogbeat | `winlogbeat` | `soc-winlogbeat-YYYY.MM.dd` |

Additional enrichments:

- `soc.severity`: `info` / `warning` / `critical` based on event type
- `soc.attack.web`: tagged on any DVWA request containing SQLi/XSS patterns
- sshd failed/accepted logins are grokked to expose `source.ip` and `user.name`
- Sysmon event IDs 1 / 3 / 11 are flagged with `event.category` hints

## Network ports

| Port | Direction | Used by |
| --- | --- | --- |
| 5044/tcp | Endpoints → ELK | Beats → Logstash |
| 5601/tcp | Analyst → ELK | Kibana UI |
| 9200/tcp | Local/optional | Elasticsearch REST (usually internal) |
| 80/tcp | Attacker → Ubuntu endpoint | DVWA |
| 22/tcp | Attacker → Ubuntu endpoint | SSH (Hydra target) |
| 3389/tcp | Attacker → Windows endpoint | RDP (optional) |

Only 5044 and 5601 must be reachable between networks. 9200 should stay on localhost.

## Security note

This lab **disables** X-Pack security (`xpack.security.enabled=false`) and runs **plain TCP** between Beats and Logstash. That's acceptable for a closed lab demo but must not be exposed to any untrusted network. See [NETWORK-SETUP.md](NETWORK-SETUP.md) for isolation options.
