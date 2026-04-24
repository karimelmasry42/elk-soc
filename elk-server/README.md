# ELK Server

Single-node Elasticsearch + Logstash + Kibana, via Docker Compose. This is the central log aggregator and analyst UI for the Mini SOC.

## Prerequisites

- **Docker Engine** 20.10+ and the **Docker Compose v2 plugin** (`docker compose`, not `docker-compose`). On Ubuntu 22.04+:
  ```bash
  sudo apt update && sudo apt install -y docker.io docker-compose-plugin
  sudo usermod -aG docker $USER && newgrp docker
  ```
- **≥ 6 GB RAM** allocated to Docker (Docker Desktop → Settings → Resources on macOS/Windows).
- `vm.max_map_count` must be at least `262144` (Elasticsearch requirement):
  ```bash
  sudo sysctl -w vm.max_map_count=262144
  # persist:
  echo "vm.max_map_count=262144" | sudo tee /etc/sysctl.d/99-elasticsearch.conf
  ```

## Start

```bash
cd elk-server
# (optional) edit .env if 2g heap is too large for your host
docker compose up -d
```

First start takes ~60 s for Elasticsearch to become healthy and another ~30 s for Kibana. Watch progress:

```bash
docker compose ps
docker compose logs -f
```

## Verify

1. **Elasticsearch:** `curl http://localhost:9200` → returns cluster JSON.
2. **Logstash:** `curl http://localhost:9600` → returns node stats; logs show `Starting server on port: 5044`.
3. **Kibana:** browse to `http://<elk-ip>:5601` — the home page loads with no login prompt (security is disabled).
4. **Pipeline syntax:** `docker compose exec logstash bin/logstash -t -f /usr/share/logstash/pipeline/` exits 0.

## Create the Data View

After at least one Beat has sent an event:

1. Kibana → **Stack Management → Data Views → Create data view**
2. Name: `soc-*`; timestamp field: `@timestamp`; save.
3. Open **Discover** and select the `soc-*` view.

Individual index patterns are also available: `soc-system-*`, `soc-auditd-*`, `soc-packetbeat-*`, `soc-winlogbeat-*`, `soc-dvwa-*`.

## Operate

```bash
docker compose logs -f logstash       # tail Logstash (most common source of errors)
docker compose restart logstash       # after editing pipeline files
docker compose down                   # stop, keep data
docker compose down -v                # stop and WIPE all indexed data
```

## Import saved objects (dashboards, detection rules)

Export from Kibana → **Stack Management → Saved Objects → Export**, save the `.ndjson` file into [kibana-exports/](kibana-exports/), commit it. On a fresh ELK instance, import from the same screen.

## What each file does

| File | Purpose |
| --- | --- |
| [docker-compose.yml](docker-compose.yml) | Orchestrates ES, Logstash, Kibana |
| [.env](.env) | Versions + JVM heap sizes + network subnet |
| [elasticsearch/elasticsearch.yml](elasticsearch/elasticsearch.yml) | ES node config (single-node, security off) |
| [logstash/pipeline/beats-input.conf](logstash/pipeline/beats-input.conf) | Receives on port 5044 |
| [logstash/pipeline/filters.conf](logstash/pipeline/filters.conf) | Parse, tag, enrich, route |
| [logstash/pipeline/elasticsearch-output.conf](logstash/pipeline/elasticsearch-output.conf) | Writes to `soc-<type>-*` indices |
| [kibana/kibana.yml](kibana/kibana.yml) | Kibana config |
| [kibana-exports/](kibana-exports/) | Dashboards and detection rules (ndjson) |
