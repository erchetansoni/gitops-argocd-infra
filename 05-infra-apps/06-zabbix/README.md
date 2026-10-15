# 📊 Zabbix Monitoring Platform (Infra App)

Enterprise-grade distributed monitoring platform deployed natively on Kubernetes via Helm and declarative GitOps (Argo CD).

---

## 🏗️ Architecture & High Availability (HA) Design

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
       │                    │             │    [ACTIVE NODE]   │             │   (zbx-proxy)      │
       └─────────┬──────────┘             └─────────┬──────────┘             └─────────┬──────────┘
                 │                                  │                                  │ (Shared emptyDir)
                 │                                  │                                  ▼
                 │                        ┌─────────┴──────────┐             ┌────────────────────┐
                 │                        │   Zabbix Server    │             │   SNMP Trapper     │
                 │                        │ (7.4-latest pgsql) │             │ (zabbix-snmptraps) │
                 │                        │   [STANDBY NODE]   │             │  UDP 162 / hostPort│
                 │                        └─────────┬──────────┘             └────────────────────┘
                 ▼                                  ▼                                  ▲
       ┌───────────────────────────────────────────────────────┐                       │
       │             TimescaleDB 2.17.2 (PG16)                 │             ┌─────────┴──────────┐
       │   • High-performance time-series metric storage       │             │   Zabbix Agent 2   │
       │   • Distributed HA cluster coordination (ha_node)     │◄────────────┤ (Node DaemonSet)   │
       └───────────────────────────────────────────────────────┘             └────────────────────┘
```

---

## 🚀 Key Architectural Features

### 1. Native Zabbix Server High Availability (HA) Cluster
* **Active-Passive Redundancy**: Two Zabbix Server instances (`zabbix-zabbix-server` and `zabbix-zabbix-server-standby`) run simultaneously against the same TimescaleDB database.
* **Database Heartbeat & Auto-Discovery**: Nodes register themselves into the database `ha_node` table via `ZBX_AUTOHANODENAME: "hostname"` and send heartbeats every 5 seconds.
* **Automatic Failover**: One node is elected **`Active`** (executes pollers, alerts, escalators), while the other node stays in **`Standby`** mode. If the active node crashes or restarts, the standby node promotes itself to Active within seconds with zero data loss.
* **Frontend Cluster Discovery**: The Web frontend automatically queries the database `ha_node` table and routes user requests directly to the active cluster node.

### 2. Decoupled SNMP Trapper via Zabbix Proxy (Approach C)
* **Dedicated SNMP Trapper Sidecar**: The `zabbix-snmptraps` container is attached as a sidecar to the **Zabbix Proxy** (`zabbix-zabbix-proxy-0`) instead of the core server.
* **HostPort 162 Ingestion**: Binds to `hostPort: 162/UDP` and Service `zabbix-snmptraps` (`162/UDP -> 1162/UDP`), receiving traps from network devices via `zbx-snmp.chetan.local:162`.
* **Zero Shared-Storage Bottleneck**: Traps are written to `/var/lib/zabbix/snmptraps/snmptraps.log` on a pod-local `emptyDir` volume, read by the proxy's `snmp trapper` daemon, and forwarded over standard encrypted TCP (port 10051) to the active Zabbix Server.
* **No Server Scaling Conflicts**: Server pods remain completely lightweight and free from `hostPort: 162` port collisions.

### 3. Active SQLite3 Zabbix Proxy (`zbx-proxy`)
* **Embedded Database Engine**: Uses `zabbix/zabbix-proxy-sqlite3:alpine-7.4.15` with a persistent volume for buffer retention.
* **Multi-Node Cluster Configuration**: Connected to the server cluster using semicolon delimiter syntax:
  ```yaml
  ZBX_SERVER_HOST: "zabbix-zabbix-server;zabbix-zabbix-server-standby"
  ```
* **Real-Time Runtime Health**: Tracks runtime state in PostgreSQL `proxy_rtdata`, continuously displaying **`Online`** (green badge) in the Web UI.

### 4. TimescaleDB 2.17.2 & PostgreSQL 16
* **Hypertable Partitioning & Compression**: Automatically compresses history and trend data, offering 10x-20x storage efficiency compared to standard relational tables.
* **10Gi Persistent Storage**: Persistent volume for long-term telemetry and metrics retention.

### 5. Zabbix Agent 2 Cluster-Wide DaemonSet
* Modern Go-based monitoring agent deployed across all Kubernetes nodes.
* Connected to both cluster nodes (`zabbix-zabbix-server,zabbix-zabbix-server-standby`) for active and passive node metrics collection.

---

## 🌐 Endpoints & Credentials

| Component | Hostname / URL | In-Cluster Service | Port / Protocol | Description |
| :--- | :--- | :--- | :--- | :--- |
| **Web UI** | `https://zabbix.chetan.local` | `zabbix-zabbix-web` | `80` (HTTP) | Web Dashboard & JSON-RPC API |
| **Server (Active)** | `zbx-srv.chetan.local` | `zabbix-zabbix-server` | `10051` (TCP) | Metric Trapper & Server Daemon |
| **Server (Standby)**| `zabbix-zabbix-server-standby` | `zabbix-zabbix-server-standby` | `10051` (TCP) | Standby HA Server Node |
| **Proxy** | `zbx-proxy.chetan.local` | `zabbix-zabbix-proxy` | `10051` (TCP) | Active SQLite3 Proxy Buffer |
| **SNMP Trapper** | `zbx-snmp.chetan.local` | `zabbix-snmptraps` | `162` (UDP) | Net-SNMP Trap Receiver |

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
  Add-Content -Path C:\Windows\System32\drivers\etc\hosts -Value "127.0.0.1 zabbix.chetan.local zbx-srv.chetan.local zbx-proxy.chetan.local zbx-snmp.chetan.local"
  ```
* **Linux / macOS**:
  ```bash
  echo "127.0.0.1 zabbix.chetan.local zbx-srv.chetan.local zbx-proxy.chetan.local zbx-snmp.chetan.local" | sudo tee -a /etc/hosts
  ```

---

## 🔍 Verification & Inspection Commands

### Check HA Cluster Nodes in Database
```bash
kubectl exec -n zabbix zabbix-postgresql-0 -- psql -U zabbix -d zabbix -c \
  "SELECT name, address, port, lastaccess, status FROM ha_node;"
```
*(Status `3` = Active, Status `0` = Standby)*

### Check Proxy Online Status
```bash
kubectl exec -n zabbix zabbix-postgresql-0 -- psql -U zabbix -d zabbix -c \
  "SELECT proxyid, lastaccess, version, state FROM proxy_rtdata;"
```
*(State `2` = Online)*

### Send a Test SNMP Trap (UDP 162)
```powershell
# PowerShell Test Script
$snmpTrapHex = "304602010104067075626c6963a739020400000001020100020100302b301306082b060102010103004307000000000003e83014060a2b06010603010104010006062b0601040101"
$bytes = [byte[]] -split ($snmpTrapHex -replace '..', '0x$& ')
$client = New-Object System.Net.Sockets.UdpClient
$client.Connect("127.0.0.1", 162)
$client.Send($bytes, $bytes.Length)
$client.Close()
```

Inspect received trap log:
```bash
kubectl exec -n zabbix zabbix-zabbix-proxy-0 -c zabbix-proxy -- cat /var/lib/zabbix/snmptraps/snmptraps.log
```

### Check Web UI Status
1. **HA Cluster Details**: Open `https://zabbix.chetan.local/zabbix.php?action=system.info` -> verify **High availability cluster: Enabled**.
2. **Proxy Status**: Open `https://zabbix.chetan.local/zabbix.php?action=proxy.list` -> verify `zbx-proxy` shows green badge **Online**.
