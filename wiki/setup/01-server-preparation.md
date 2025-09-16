# Server Preparation

| Goal | Provision a hardened Linux host that can sustain OpsiSuit services and the OPSI stack. |
| --- | --- |
| Prerequisites | SSH access with sudo, network reachability to management VLAN, capacity planning metrics. |
| Deliverables | Patched OS, configured network interfaces, storage layout, baseline security controls. |

## Scope
This guide establishes the physical or virtual foundation required before deploying any OPSI components. It covers hardware sizing, operating system preparation, network planning, and baseline security controls.

## Host Requirements
1. **Operating System:** Debian 12 or Ubuntu 22.04 LTS (minimal install). Disable unattended GUI components.
2. **Hardware Baseline:**
   - CPU: 4 vCPU (8+ recommended for large estates)
   - Memory: 16 GB (scale with concurrent deployments)
   - Storage: Fast SSD for database and package cache; optional object storage integration.
3. **Essential Packages:**
   ```bash
   sudo apt update && sudo apt install -y curl gnupg lsb-release ca-certificates git
   ```
4. **Time Synchronisation:** Enable `systemd-timesyncd` or an NTP client to ensure consistent timestamps across OPSI services.

## Network Foundation
- **Addressing Plan:** Allocate static IPs for the OPSI server, PXE/TFTP endpoint, and database. Document VLAN tags and routing rules.
- **DNS Entries:** Pre-create `A` and `PTR` records for the OPSI server (`opsi.example.com`) and auxiliary services (database, proxy).
- **Firewall Baseline:**
  - Allow inbound `22/tcp` (SSH), `80/443/tcp` (HTTP/S), `69/udp` (TFTP), `4011/udp` (PXE proxy), database port (`5432/tcp` or `3306/tcp`).
  - Restrict management services to trusted subnets.
- **DHCP Planning:** Decide whether OPSI will run its own DHCP server or integrate via DHCP relay. Record existing DHCP scope details.

## Storage Planning
| Component | Capacity Notes | Storage Type |
| --- | --- | --- |
| OPSI repository | Size grows with package catalog; plan > 200 GB for Windows ISO storage. | NAS or object storage mounted via NFS/SMB/S3. |
| Database | Estimate 2–5 GB per 1,000 clients. | SSD-backed block storage with redundancy. |
| Logs & metrics | Retain 30–90 days. | Separate volume or log aggregation pipeline. |
| Netboot images | Each OS image 5–8 GB; keep staging and production copies. | SSD or fast NAS. |

> **Tip:** Separate the Docker data directory (`/var/lib/docker`) from package storage to simplify scaling.

## Security Baseline
1. Enforce SSH key-based authentication and disable password login.
2. Enable unattended security updates:
   ```bash
   sudo apt install -y unattended-upgrades
   sudo dpkg-reconfigure --priority=low unattended-upgrades
   ```
3. Install and configure `ufw` or another firewall with default deny inbound.
4. Register the host in your monitoring system (even before OPSI is deployed) to track CPU, RAM, and disk usage.

## Validation Checklist
- [ ] OS is patched, with `uname -a` and `lsb_release -a` recorded in documentation.
- [ ] Static IP, DNS, and gateway verified via `ping` and `dig` tests.
- [ ] Firewall rules saved and reviewed by a peer.
- [ ] Storage volumes mounted with correct ownership and available space checked (`df -h`).
- [ ] Credentials and sensitive notes stored in the organization’s password manager.

Once these items are confirmed, proceed to [Container Platform & Topology](02-container-platform.md).
