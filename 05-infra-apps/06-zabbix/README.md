# 📊 Zabbix Monitoring Platform (Infra App)

Enterprise-grade distributed monitoring platform deployed natively on Kubernetes via Helm and declarative GitOps (Argo CD).

---

## 🏗️ Architecture & Components

```
                              ┌─────────────────────────────────────────┐
                              │     Traefik Gateway (main-gateway)      │
                              │     Port 443 Wildcard TLS Termination   │
                              └────────────────────┬────────────────────┘
                                                   │
                ┌──────────────────────────────────┼──────────────────────────────────┐
                │ (zabbix.chetan.local)            │ (zbx-srv.chetan.local)           │ (zbx-proxy.chetan.local)
                ▼                                  ▼                                  ▼
      ┌────────────────────┐             ┌────────────────────┐             ┌────────────────────┐
      │   Zabbix Web UI    │             │   Zabbix Server    │             │    Zabbix Proxy    │
      │  (Nginx Frontend)  │◄───────────►│ (7.4-latest pgsql) │◄────────────┤ (SQLite3 Active)   │
      └─────────┬──────────┘             └─────────┬──────────┘             └────────────────────┘
                │                                  │                                  ▲
                │                                  │                                  │
                ▼                                  ▼                                  │
      ┌───────────────────────────────────────────────────────┐             ┌────────────────────┐
      │             TimescaleDB 2.17.2 (PG16)                 │             │   Zabbix Agent 2   │
      │   High-performance time-series metric storage         │             │ (Node DaemonSet)   │
      └───────────────────────────────────────────────────────┘             └────────────────────┘
```

### Components Included

1. **Zabbix Server** (`zabbix/zabbix-server-pgsql:alpine-7.4-latest`):
   - Core monitoring engine, alerting, and metric collection daemon.
   - Configured with `ENABLE_TIMESCALEDB: "true"` and `ZBX_DBEXTENDEDSTATUS: "1"` for native hypertable compression and partitioning.
   - In-cluster service: `zabbix-zabbix-server.zabbix.svc.cluster.local:10051`.

2. **Zabbix Web UI** (`zabbix/zabbix-web-nginx-pgsql:alpine-7.4-latest`):
   - Fast, modern Nginx web frontend providing dashboards, templates, graphs, and the JSON-RPC API (`/api_jsonrpc.php`).
   - Exposed via Traefik Gateway API `HTTPRoute` at `https://zabbix.chetan.local`.

3. **TimescaleDB** (`timescale/timescaledb:2.17.2-pg16`):
   - PostgreSQL 16 extended with TimescaleDB time-series engine.
   - Automatically compresses history and trend data, providing 10-20x storage efficiency compared to standard relational tables.
   - Persistent volume claim of 10Gi for long-term telemetry retention.

4. **Zabbix Proxy** (`zabbix/zabbix-proxy-sqlite3:alpine-7.4-latest`):
   - Lightweight active proxy utilizing a local embedded SQLite3 database.
   - Buffers metric collection independently and forwards telemetry to Zabbix Server over port 10051.

5. **Zabbix Agent 2** (`zabbix/zabbix-agent2:alpine-7.4-latest`):
   - Modern Go-based monitoring agent deployed as a cluster-wide Kubernetes `DaemonSet`.
   - Collects OS-level node metrics (CPU, RAM, disk I/O, network) and Kubernetes container statistics.

---

## 🌐 Endpoints & Credentials

| Component | Hostname / URL | In-Cluster Service | Port | Description |
| :--- | :--- | :--- | :--- | :--- |
| **Web UI** | `https://zabbix.chetan.local` | `zabbix-zabbix-web` | `80` (HTTP) | Web Dashboard & REST/JSON-RPC API |
| **Server** | `zbx-srv.chetan.local` | `zabbix-zabbix-server` | `10051` (TCP) | Metric Trapper & Server Daemon |
| **Proxy** | `zbx-proxy.chetan.local` | `zabbix-zabbix-proxy` | `10051` (TCP) | Active SQLite3 Proxy Buffer |

### Default Credentials
* **Web UI Username**: `Admin` (case-sensitive)
* **Web UI Password**: `zabbix`
* **TimescaleDB User**: `zabbix`
* **TimescaleDB Password**: `Zabbix12345`

---

## 🚀 Installation & Usage

### 1. Automated Installation
Run the dedicated installation script:
```bash
./05-infra-apps/06-zabbix/install-zabbix.sh
```

### 2. Local DNS Setup
Ensure local host resolution is added to your hosts file:
* **Windows (PowerShell as Admin)**:
  ```powershell
  Add-Content -Path C:\Windows\System32\drivers\etc\hosts -Value "127.0.0.1 zabbix.chetan.local zbx-srv.chetan.local zbx-proxy.chetan.local"
  ```
* **Linux / macOS**:
  ```bash
  echo "127.0.0.1 zabbix.chetan.local zbx-srv.chetan.local zbx-proxy.chetan.local" | sudo tee -a /etc/hosts
  ```

### 3. Verification
```bash
kubectl get pods -n zabbix
kubectl get httproute -n zabbix
```
