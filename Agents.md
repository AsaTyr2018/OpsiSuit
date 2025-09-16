# Agent: OpsiSuit

## Overview

**Name:** OpsiSuit
**Purpose:** Automated setup and management of a complete OPSI infrastructure (OS deployment, application deployment, inventory).
**Target platform:** Linux servers (preferably Debian / Ubuntu / CentOS / RHEL etc.), ideally under Docker or using containerization.

OpsiSuit handles:

- Installation and configuration of the OPSI server and all related components
- Provisioning of OPSI clients / agents on target machines
- Management of application deployments
- OS deployment (installation, imaging, partitioning, etc.)
- Inventory: hardware, software, configuration

---

## Components & Architecture

| Component | Description |
|-----------|-------------|
| **OPSI Server** | Central component that controls deployment, inventory, and clients. |
| **Database** | e.g., MariaDB / MySQL / PostgreSQL for storing OPSI data. |
| **Web Frontend / Management UI** | Web interface for managing images, packages, clients, etc. |
| **Tftp / PXE + Netboot Components** | For OS deployment over the network, boot images, etc. |
| **Package Repository / Package Management** | Stores for software packages, updates, etc. |
| **Client Agent** | Installed on target machines to execute deployment, inventory, etc. |
| **Inventory Module** | Script / agent that collects hardware and software data and reports back. |

If possible, run everything in containers with a clear separation, e.g., database, web frontend, PXE/TFTP, agent, etc.

---

## Installation and Setup Flow

1. **Server preparation**
   - Linux server with a minimal installation
   - Base packages: Docker / Docker Compose (or Podman), Git, Curl, possibly firewall / network configuration
   - Prepare the network (e.g., DHCP + PXE, static IP, DNS if required)

2. **Containerized components (if Docker is used)**
   - Define Docker Compose / stack: services for OPSI backend, database, web frontend, PXE/TFTP, optionally proxy/load balancer
   - Configure persistent volumes (e.g., database data, logs, images)
   - Networks and ports (e.g., HTTP/HTTPS, TFTP, DHCP, etc.)

3. **OPSI server installation & configuration**
   - Add OPSI package source
   - Install the OPSI server components
   - Set up the database (schema, user, permissions)
   - Configure the web UI, SSL (e.g., using Let's Encrypt)

4. **PXE / Netboot setup**
   - Configure TFTP / DHCP (if not already available)
   - Prepare netboot images
   - Boot configuration (e.g., Linux kernel + initrd)

5. **Client agent setup**
   - Automatically roll out the agent to target machines (e.g., via SSH, via OPSI itself)
   - Ensure that the inventory module runs and regularly sends data back to the server

6. **App and OS deployment setup**
   - Define OS images (configuration, partitioning, drivers, etc.)
   - Application package repositories (Windows / Linux applications)
   - Define deployment scripts / tasks
   - Rollout / update management

7. **Inventory**
   - Collect hardware data (CPU, RAM, disks, network cards, etc.)
   - Collect installed software and versions
   - Logic to detect deviations / missing updates

8. **Monitoring & Backup**
   - Collect logs, monitor services (e.g., via Prometheus, Grafana or simple monitoring)
   - Back up the database, configuration, and images

---

## Style Guidelines & Best Practices for the Agent

- **Idempotence:** Running actions multiple times must not create an error state.
- **Configurability:** As many parameters as possible should be configurable externally (e.g., .ENV, YAML, etc.): ports, paths, database credentials, network, etc.
- **Modularity:** Each part (database, web UI, PXE, agent, inventory) should be as isolated and interchangeable as possible.
- **Security:**
  - SSL/TLS for web interfaces
  - Secure credentials, ideally secrets management
  - Restricted access to PXE/TFTP, etc.
- **Logging & error handling:** Clear logs, understandable error messages, recovery paths.
- **Documentation & testing:** Each component should be documented (setup, usage) with automated tests / validations where possible.

---

## Technical Notes & Defaults

- **Operating systems (server):** Debian 12 / Ubuntu LTS / CentOS / Rocky Linux
- **Database:** MariaDB or PostgreSQL, standby or replication optional
- **Container orchestration:** Docker + Docker Compose, optionally Kubernetes for large setups
- **Web UI:** Preferably the standard OPSI web installer / OPSI ConfigAPI, optionally a custom dashboard
- **Network services:**
  - DHCP server or integration with an existing DHCP service
  - PXE/TFTP over UDP port 69 + corresponding ports
  - HTTP/HTTPS for file and package delivery
- **Agents:** Support Windows and Linux clients
- **Inventory interval:** e.g., daily inventory; for large environments possibly hourly or as required

---

## Suggested Folder Structure / Repository Layout

A possible structure for a Git repository:

```
opsisuit/
├── docker/
│   ├── docker-compose.yml
│   ├── .env.sample
│   └── services/
│       ├── server/
│       ├── webui/
│       ├── db/
│       ├── pxe/
│       └── agent/
├── configs/
│   ├── opsi.conf
│   ├── pxe/
│   └── client_agent.conf
├── scripts/
│   ├── setup_server.sh
│   ├── setup_agent.sh
│   └── inventory_collector.sh
├── images/
│   └── os_templates/
├── docs/
│   ├── installation.md
│   ├── usage.md
│   └── troubleshooting.md
└── tests/
├── ci_tests/
└── integration_tests/

````

---

## Interfaces & API

- Use the OPSI ConfigAPI for automated control (packages, clients, tasks).
- REST API endpoint in the agent to submit inventory data.
- Webhooks or events for status changes or errors if required.

---

## Example Configuration Variables (ENV / YAML)

```yaml
server:
  hostname: "opsi.example.com"
  ip: "192.168.1.10"

database:
  type: "postgresql"
  host: "db"
  port: 5432
  user: "opsiuser"
  password: "securepassword"
  dbname: "opsi_db"

pxe:
  tftp_root: "/var/lib/tftpboot"
  dhcp_conf: "/etc/dhcp/dhcpd.conf"
  pxe_images_dir: "/pxe_images"

agent:
  poll_interval_minutes: 60
  secret_key: "some_long_secret"

webui:
  port: 443
  ssl_cert: "/etc/letsencrypt/live/opsi.pem"
  ssl_key: "/etc/letsencrypt/live/opsi-key.pem"
````

---

## Tasks / User Stories

To guide the development of the agent, a few user stories:

* As an administrator I want to set up the entire OPSI server in a Docker setup with a single command.
* As an administrator I want new clients to be inventoried automatically as soon as they appear on the network.
* As an administrator I want to define OS images and deploy them to new machines.
* As an administrator I want to roll out applications to clients and control updates.
* As an administrator I want access to logs / status views through a web UI.

---

## Summary

OpsiSuit aims to be a **complete, modular, automated solution** that allows you to quickly set up an OPSI infrastructure on Linux (ideally Docker), manage OS & app deployments, and handle inventory. Security, configurability, and maintainability are core elements.

