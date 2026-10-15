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

---

## 📂 File Inventory & Directory Structure

```
05-infra-apps/06-zabbix/
├── install-zabbix.sh           # Automated installer script (Helm, HTTPRoute, DB bootstrap)
├── zabbix-values.yaml          # Helm values (HA nodes, TimescaleDB, Proxy SNMP sidecar)
├── zabbix-httproute.yaml       # Gateway API HTTPRoute connecting zabbix.chetan.local
├── zabbix-application.yaml     # Standalone Argo CD Application manifest for GitOps
└── README.md                   # Comprehensive architecture, operational guide & verification
```

### Detailed Breakdown of Files

1. **[`install-zabbix.sh`](install-zabbix.sh)**:
   * **Purpose**: Orchestrates the standalone or pre-Argo CD automated installation of the entire Zabbix monitoring platform.
   * **Key Capabilities**:
     * Automatically sources parent `.env` configuration via `load-env.sh`.
     * Automatically detects local offline Helm chart tarballs (`airgap/charts/zabbix-*.tgz`) or connects to the online repository (`zabbix-community`).
     * Executes `helm upgrade --install` with custom values and database secrets.
     * Applies Gateway API `HTTPRoute` with automatic domain interpolation (`sed s|chetan.local|${MAIN_DOMAIN}|g`).
     * Monitors workload rollouts for deployments (`server`, `server-standby`, `web`), statefulsets (`postgresql`, `proxy`), and daemonsets (`agent`).
     * Bootstraps PostgreSQL database tables (`interface`, `proxy`, `proxy_rtdata`) so that the active proxy (`zbx-proxy`) and server agent interface are instantly `Online` without manual Web UI setup.
     * Displays a clean verification summary with URLs, credentials, and DNS records.

2. **[`zabbix-values.yaml`](zabbix-values.yaml)**:
   * **Purpose**: Centralized Helm configuration defining all components and container parameters.
   * **Key Configurations**:
     * `postgresql`: Deploys TimescaleDB 2.17.2 on PostgreSQL 16 with 10Gi persistent storage and 150 max connections.
     * `zabbixServer`: Configures the primary active server pod with `ZBX_AUTOHANODENAME: hostname`, `ENABLE_TIMESCALEDB: "true"`, and `ZBX_DBEXTENDEDSTATUS: "1"`.
     * `extraManifests`: Declares the secondary standby server node (`Deployment/zabbix-zabbix-server-standby`) enabling native active-passive HA cluster mode.
     * `zabbixProxy`: Configures the SQLite3 proxy daemon, attaches the `zabbix-snmptraps` sidecar container binding to `hostPort: 162/UDP`, mounts shared `snmptraps-dir` (`emptyDir`), creates Service `zabbix-snmptraps`, and sets `ZBX_SERVER_HOST: "zabbix-zabbix-server;zabbix-zabbix-server-standby"`.
     * `zabbixAgent`: Deploys modern Go-based Agent 2 as a cluster-wide Kubernetes `DaemonSet` monitoring all nodes.
     * `zabbixWeb`: Configures Nginx frontend, connects to cluster servers, and enables Gateway API HTTP routing.
     * `zabbixWebservice`: Deploys Google Chrome headless web service for scheduled dashboard and report PDF generation.

3. **[`zabbix-httproute.yaml`](zabbix-httproute.yaml)**:
   * **Purpose**: Kubernetes Gateway API `HTTPRoute` resource attaching `zabbix.chetan.local` to `Gateway/main-gateway` in the `default` namespace.
   * **Routing**: Matches path `/` (PathPrefix) and forwards cleartext traffic to Service `zabbix-zabbix-web:80`, with TLS terminated at the Gateway using the `*.chetan.local` wildcard certificate.

4. **[`zabbix-application.yaml`](zabbix-application.yaml)**:
   * **Purpose**: Declarative Argo CD `Application` Custom Resource manifest for GitOps management.
   * **Tracking**: Points directly to Helm repository `https://zabbix-community.github.io/helm-zabbix` chart `zabbix` version `7.1.0` with full in-line `valuesObject`.
   * **Sync Policies**: Configured with `automated` sync, `prune: false`, `selfHeal: true`, and sync-wave `2` for seamless platform orchestration.

---

## 🛠️ Automated Installer Script Guide (`install-zabbix.sh`)

### How to Use

The script can be executed from Git Bash, Linux/macOS terminal, or Windows PowerShell:

#### 1. Standard Execution (Default Settings)
```bash
./05-infra-apps/06-zabbix/install-zabbix.sh
```

#### 2. Custom Domain Execution
```bash
MAIN_DOMAIN="mycompany.local" ./05-infra-apps/06-zabbix/install-zabbix.sh
```

#### 3. Custom Credentials & Namespace
```bash
ZABBIX_NAMESPACE="monitoring" \
ZABBIX_ADMIN_PASSWORD="SuperSecretPassword123" \
ZABBIX_DB_PASSWORD="DbSecretPassword123" \
./05-infra-apps/06-zabbix/install-zabbix.sh
```

#### 4. Windows PowerShell Execution
```powershell
bash 05-infra-apps/06-zabbix/install-zabbix.sh
```

---

### Command-Line Arguments & Flags

`install-zabbix.sh` is designed for seamless GitOps and CI/CD pipelines following twelve-factor app principles:
* **Arguments**: Accepts zero mandatory positional arguments.
* **Auto-Discovery**: Automatically searches parent directories for `load-env.sh` and extracts variables from root `.env`.
* **Path Conversion**: Automatically detects MSYS2/Git Bash environments and invokes `cygpath -w` to ensure Windows paths are passed properly to Helm and kubectl.
* **Offline Detection**: Automatically probes for offline `.tgz` chart archives in `airgap/charts/` before attempting to reach external Helm repositories.

---

### Configuration Variables & Environment Variables

All variables have robust built-in defaults and can be overridden via shell environment variables or `.env`:

| Environment Variable | Default Value | Description |
| :--- | :--- | :--- |
| **`MAIN_DOMAIN`** | `chetan.local` | Base domain used to derive all service FQDNs. |
| **`ZABBIX_HOST`** | `zabbix.${MAIN_DOMAIN}` | FQDN for the Web UI and Gateway API HTTPRoute (`zabbix.chetan.local`). |
| **`ZABBIX_SRV_HOST`** | `zbx-srv.${MAIN_DOMAIN}` | FQDN for the active server daemon (`zbx-srv.chetan.local`). |
| **`ZABBIX_PROXY_HOST`** | `zbx-proxy.${MAIN_DOMAIN}` | FQDN for the proxy buffer daemon (`zbx-proxy.chetan.local`). |
| **`ZABBIX_NAMESPACE`** *(or `NAMESPACE`)* | `zabbix` | Target Kubernetes namespace. Created automatically if missing. |
| **`ZABBIX_RELEASE_NAME`** *(or `RELEASE_NAME`)* | `zabbix` | Helm release name. |
| **`ZABBIX_HELM_REPO_URL`** | `https://zabbix-community.github.io/helm-zabbix` | Official Helm chart repository URL. |
| **`ZABBIX_HELM_CHART`** | `zabbix-community/zabbix` | Helm chart reference name. |
| **`ZABBIX_CHART_VERSION`** | `7.1.0` | Target Helm chart version (app version 7.4.15). |
| **`ZABBIX_ADMIN_USER`** *(or `ZABBIX_USER`)* | `Admin` | Initial administrative username for the Web UI. |
| **`ZABBIX_ADMIN_PASSWORD`** *(or `ZABBIX_PASS`)* | `zabbix` | Initial administrative password for the Web UI. |
| **`ZABBIX_DB_PASSWORD`** *(or `ZABBIX_DB_PASS`)* | `Zabbix12345` | PostgreSQL database password for the `zabbix` database user. |

---

### Step-by-Step Script Execution Flow

When executed, `install-zabbix.sh` carries out the following operational steps:

1. **Step 0: Helm Chart Resolution**: Probes `airgap/charts/zabbix-7.1.0.tgz`. If present, installs 100% offline. If missing, adds and updates the `zabbix-community` repository.
2. **Step 1: Helm Deployment**: Executes `helm upgrade --install` applying `zabbix-values.yaml` and sets the database password with a 10-minute rollout timeout.
3. **Step 2: Gateway API HTTPRoute Application**: Applies `zabbix-httproute.yaml`. If `MAIN_DOMAIN` is overridden, it dynamically rewrites the hostname via `sed` before applying with `--server-side --force-conflicts`.
4. **Step 3: Workload Rollout Readiness**: Monitors rollouts using `kubectl rollout status` for:
   * Deployments: `zabbix-zabbix-server`, `zabbix-zabbix-server-standby`, `zabbix-zabbix-web`
   * StatefulSets: `zabbix-postgresql`, `zabbix-zabbix-proxy`
   * DaemonSet: `zabbix-zabbix-agent`
5. **Step 3b: Automated Database Bootstrapping**: Connects to `zabbix-postgresql-0` and executes idempotent SQL queries to:
   * Update the primary host interface to use DNS `zabbix-zabbix-agent` instead of static IP `127.0.0.1`.
   * Register proxy name `zbx-proxy` in the `proxy` table.
   * Mark `proxy_rtdata` with `state: 2` (Online) and `version: 70415` so the Web UI displays green status immediately.
6. **Step 4: Summary & Route Display**: Prints active HTTPRoutes, running pods, URLs, credentials, and required `/etc/hosts` mappings.

---

## 🌐 Local DNS Setup
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

---

## 🔌 Adding Devices, Network Switches, PLCs & Hosts into Zabbix

Zabbix supports agentless polling (SNMP, Modbus, ICMP, IPMI), event-driven ingestion (SNMP Traps), and agent-based telemetry (Zabbix Agent 2). 

### Monitoring Protocol Matrix

| Target Type | Examples | Primary Protocols | Port / Transport | Recommended Zabbix Template | Proxy Recommendation |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Network Switches / Routers** | Cisco Catalyst, Juniper, Arista, MikroTik, HP/Aruba | SNMP v2c / v3, SNMP Traps | `161/UDP` (Poll)<br>`162/UDP` (Traps) | `Cisco IOS by SNMP`<br>`Network Generic Device SNMP`<br>`MikroTik by SNMP` | **`zbx-proxy`** (Keeps SNMP traffic local to network segment) |
| **Industrial PLCs & Controllers** | Siemens S7-1200/1500, Schneider M241/M251, Rockwell/Allen-Bradley, WAGO | Modbus TCP, SNMP, MQTT, OPC-UA | `502/TCP` (Modbus)<br>`161/UDP` (SNMP)<br>`1883/TCP` (MQTT) | Modbus TCP Templates<br>`modbus.get[...]` Plugin<br>Generic SNMP / Custom MIB | **`zbx-proxy`** (Essential for OT/IT isolation & firewall traversal) |
| **Linux / Windows Hosts & VMs** | Ubuntu, Debian, RHEL, Windows Server | Zabbix Agent 2 (Active/Passive) | `10050/TCP` (Passive)<br>`10051/TCP` (Active) | `Linux by Zabbix agent active`<br>`Windows by Zabbix agent active` | Either `(no proxy)` or `zbx-proxy` |
| **Unmanaged / Edge Devices** | Printers, IP Cameras, PDU, UPS | ICMP Ping, SNMP, HTTP/REST | `ICMP`<br>`161/UDP` (SNMP) | `ICMP Ping`<br>`APC UPS by SNMP` | **`zbx-proxy`** |

---

### 1. 🖧 How to Add Network Switches & Routers (SNMP)

#### Step 1: Configure SNMP on Your Switch
Enable SNMP v2c/v3 and configure the SNMP Trap target on your network switch.

* **Cisco IOS Example**:
  ```text
  enable
  configure terminal
  snmp-server community MyCompanyCommunity RO
  snmp-server location DataCenter-Rack-04
  snmp-server contact devops@chetan.local
  ! Send SNMP Traps to Zabbix Proxy Sidecar
  snmp-server host 127.0.0.1 version 2c MyCompanyCommunity
  snmp-server enable traps
  end
  write memory
  ```

* **MikroTik RouterOS Example**:
  ```text
  /snmp community add name=MyCompanyCommunity addresses=0.0.0.0/0 read-access=yes
  /snmp set enabled=yes location="Server Room" contact="admin@chetan.local" trap-version=2 trap-target=127.0.0.1 trap-community=MyCompanyCommunity
  ```

#### Step 2: Add Switch Host in Zabbix Web UI
1. Open [https://zabbix.chetan.local](https://zabbix.chetan.local) and log in (`Admin` / `zabbix`).
2. Navigate to **Data collection > Hosts** and click **Create host** (top-right).
3. **Host Tab**:
   * **Host name**: `core-switch-01`
   * **Visible name**: `Core Switch 01 (Rack 4)`
   * **Host groups**: Select `Templates/Network devices` or create `Switches`.
   * **Interfaces**: Click **Add** -> select **SNMP**:
     * **IP address**: Device LAN IP (e.g., `192.168.1.50`).
     * **DNS name**: Leave blank or set FQDN.
     * **Connect to**: Select **IP**.
     * **Port**: `161`.
     * **SNMP version**: `SNMPv2`.
     * **SNMP community**: `{$SNMP_COMMUNITY}` (uses a secure macro).
   * **Monitored by proxy**: Select **`zbx-proxy`** *(Recommended: Proxy performs local polling and forwards metrics securely)*.
4. **Templates Tab**:
   * Link one of the built-in official templates:
     * `Cisco IOS by SNMP` (or `Cisco IOS XE by SNMP`)
     * `Network Generic Device SNMP` (interfaces, CPU, memory, uptime for any vendor)
     * `Juniper by SNMP`, `Aruba by SNMP`, `MikroTik by SNMP`
5. **Macros Tab**:
   * Click **Inherited and host macros**.
   * Find or add `{$SNMP_COMMUNITY}` and set its value to your community string (e.g. `MyCompanyCommunity`).
6. Click **Add**.

#### Step 3: Verify SNMP Polling & Traps
* **Check Interface Availability**: In **Data collection > Hosts**, the **SNMP** icon next to `core-switch-01` will turn **green** within 30–60 seconds.
* **Test SNMP Connectivity from Proxy**:
  ```bash
  kubectl exec -n zabbix zabbix-zabbix-proxy-0 -c zabbix-proxy -- \
    snmpwalk -v2c -c MyCompanyCommunity 192.168.1.50 1.3.6.1.2.1.1.1.0
  ```
* **Verify Traps**: Any link-down or power-supply alert generated by the switch arrives at `zbx-snmp.chetan.local:162/UDP`, logs to `/var/lib/zabbix/snmptraps/snmptraps.log`, and triggers alarms in **Monitoring > Problems**.

---

### 2. 🏭 How to Add Industrial PLCs & Automation Equipment (OT)

Industrial environments (factory floors, water treatment, packaging lines) typically feature **Programmable Logic Controllers (PLCs)** from Siemens, Schneider Electric, Allen-Bradley (Rockwell), Omron, or WAGO.

#### Approach A: Modbus TCP Protocol (Standard Port 502)
Modbus TCP is the universal communication protocol used across industrial automation to read sensor values, motor RPM, coil states, and fault codes.

1. **How Zabbix Collects Modbus Telemetry**:
   Zabbix Agent 2 includes a native, high-performance **Modbus Plugin**.
   The polling syntax is:
   ```text
   modbus.get[endpoint,slave_id,function_code,address,count]
   ```
   * **Function Codes**:
     * `1` = Read Coils (Digital outputs, discrete status: On/Off)
     * `2` = Read Discrete Inputs (Digital inputs: sensor active/inactive)
     * `3` = Read Holding Registers (Analog setpoints, motor speeds, temperatures)
     * `4` = Read Input Registers (Analog sensor measurements: pressure, flow rate)

2. **Step-by-Step Configuration in Zabbix**:
   * In **Data collection > Hosts > Create host**:
     * **Host name**: `plc-line1-assembly`
     * **Monitored by proxy**: `zbx-proxy`
     * **Interfaces**: Add **Agent** interface with IP of a machine running Zabbix Agent 2 (or in-cluster proxy).
   * **Create Modbus Items**:
     * Go to the host's **Items** -> click **Create item**:
       * **Name**: `Motor Line 1 Speed (RPM)`
       * **Type**: `Zabbix agent` (or `Zabbix agent (active)`)
       * **Key**: `modbus.get[tcp://192.168.10.50:502,1,3,100,1]` *(Reads Holding Register 100 from Slave 1)*
       * **Type of information**: `Numeric (unsigned)`
       * **Update interval**: `5s`
     * To extract specific registers from a JSON array returned by Modbus batch reads:
       * In item **Preprocessing**, add: `JSONPath: $.[0]`

#### Approach B: SNMP on Industrial PLCs
Modern PLCs (Siemens S7-1200 / S7-1500 with CP modules, Schneider Modicon M241/M251) have embedded SNMP daemons:

1. **Enable SNMP in Engineering Software**:
   * **Siemens TIA Portal**: Go to PLC **Device Configuration** -> **PROFINET Interface** -> **SNMP** -> check **Enable SNMP**.
   * Set Community String (e.g. `public` or custom).
2. **Add to Zabbix**:
   * Add host with **SNMP Interface** (Port `161`).
   * Link template: `Network Generic Device SNMP` or vendor MIB template.
   * Monitored by proxy: `zbx-proxy`.

#### Approach C: MQTT / Industrial IoT Gateways
For smart sensors, vibration monitors, and IoT energy meters publishing to an MQTT broker:
* **Item Key**:
  ```text
  mqtt.get["tcp://broker.chetan.local:1883","factory/line1/plc/telemetry"]
  ```
* Use JSONPath preprocessing to extract temperature, current, and vibration metrics into individual Zabbix items.

---

### 3. 🖥️ How to Add Linux & Windows Hosts (Servers & VMs)

#### Step 1: Install Zabbix Agent 2 on the Target Host

* **Linux (Ubuntu / Debian)**:
  ```bash
  # Download official Zabbix repository package:
  wget https://repo.zabbix.com/zabbix/7.4/ubuntu/pool/main/z/zabbix-release/zabbix-release_latest_7.4+ubuntu24.04_all.deb
  sudo dpkg -i zabbix-release_latest_7.4+ubuntu24.04_all.deb
  sudo apt update
  sudo apt install -y zabbix-agent2
  ```

* **Linux (RHEL / AlmaLinux / Rocky Linux 9)**:
  ```bash
  sudo rpm -Uvh https://repo.zabbix.com/zabbix/7.4/rhel/9/x86_64/zabbix-release-latest-7.4.el9.noarch.rpm
  sudo dnf install -y zabbix-agent2
  ```

* **Windows**:
  Download the MSI installer from [Zabbix Download Portal](https://www.zabbix.com/download_agents) and install as a Windows Service.

#### Step 2: Configure `zabbix_agent2.conf`
Edit `/etc/zabbix/zabbix_agent2.conf` (or `C:\Program Files\Zabbix Agent 2\zabbix_agent2.conf` on Windows):

```ini
# Passive Checks (Zabbix Server / Proxy pulls metrics from Agent on port 10050)
Server=zbx-srv.chetan.local,zbx-proxy.chetan.local

# Active Checks (Agent initiates outbound connection on port 10051)
ServerActive=zbx-srv.chetan.local;zbx-proxy.chetan.local

# Hostname MUST match the "Host name" defined in the Zabbix Web UI
Hostname=web-server-prod-01
```

Restart the agent service:
```bash
sudo systemctl restart zabbix-agent2
sudo systemctl enable zabbix-agent2
```

#### Step 3: Register Host in Zabbix Web UI
1. Go to **Data collection > Hosts** -> **Create host**.
2. **Host name**: `web-server-prod-01` (case-sensitive match with `Hostname` in config).
3. **Templates**: Link `Linux by Zabbix agent active` (or `Windows by Zabbix agent active`).
4. **Interfaces**: Click **Add** -> **Agent**:
   * **IP address**: Target server IP.
   * **Port**: `10050`.
5. **Monitored by proxy**: Select `zbx-proxy` (or `(no proxy)` if communicating directly with the HA server cluster).
6. Click **Add**. Within 30 seconds, the **ZBX** badge turns green and metrics begin streaming.

---

### 4. 🛡️ Why Route Through `zbx-proxy`? (Enterprise Architecture)

In this infrastructure, we recommend setting **Monitored by proxy: `zbx-proxy`** for network switches, branch offices, and factory floor PLCs:

```
[ Factory Floor / Corporate LAN ]                [ Kubernetes Ingress ]
Switches (SNMP :161)    ──┐
PLCs (Modbus :502)      ──┼──► zbx-proxy (SQLite3) ──── TCP 10051 ────► Zabbix HA Cluster
SNMP Traps (:162 UDP)   ──┘       (Sidecar Trapper)
```

1. **Firewall & Security Hardening**:
   * Only **one outbound TCP port (10051)** needs to be opened between your network and the Kubernetes cluster.
   * Internal switches and OT PLCs never need their management IPs exposed outside their local VLAN.
2. **Local SNMP Trap Aggregation**:
   * UDP packets cannot be routed reliably over high-latency WAN connections. The proxy receives traps locally and forwards them over encrypted TCP.
3. **Buffer During Maintenance & Failovers**:
   * If Kubernetes nodes restart or the Zabbix Server fails over between HA nodes, `zbx-proxy` caches telemetry in its local SQLite3 database and streams all buffered data once the connection resumes, guaranteeing **zero data loss**.
