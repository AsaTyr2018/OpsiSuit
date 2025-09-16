# Container Platform & Topology

| Goal | Provision the container runtime, compose stack, and logical topology for OpsiSuit services. |
| --- | --- |
| Prerequisites | Completed [Server Preparation](01-server-preparation.md), sudo access, storage volumes mounted. |
| Deliverables | Docker engine with compose plugin, network overlays, baseline `docker-compose.yml`, secrets storage. |

## Scope
This stage installs the container engine, defines how services communicate, and documents the runtime topology. It forms the execution environment for all higher-level OPSI components.

## Container Runtime Installation
1. **Install Docker Engine:**
   ```bash
   curl -fsSL https://get.docker.com | sudo sh
   sudo systemctl enable --now docker
   ```
2. **Add Admin Users:**
   ```bash
   sudo usermod -aG docker <your-admin-user>
   ```
3. **Configure Daemon:** Create `/etc/docker/daemon.json`:
   ```json
   {
     "log-driver": "json-file",
     "log-opts": {
       "max-size": "10m",
       "max-file": "5"
     },
     "default-address-pools": [
       {"base": "172.30.0.0/16", "size": 24}
     ]
   }
   ```
   Reload with `sudo systemctl restart docker`.

## Service Topology
| Service | Role | Ports | Scaling Notes |
| --- | --- | --- | --- |
| `opsi-server` | Core OPSI backend and ConfigAPI | 4447/tcp, 80/443/tcp | Stateful; single replica with failover node optional. |
| `opsi-db` | MariaDB/PostgreSQL datastore | 5432/tcp or 3306/tcp | Prefer managed DB or replicated pair. |
| `opsi-webui` | Management UI / dashboards | 443/tcp | Stateless; scale horizontally behind proxy. |
| `opsi-pxe` | TFTP/PXE service | 69/udp, 4011/udp | Requires host networking or MAC VLAN support. |
| `opsi-repository` | Package mirror / file share | 80/tcp, 445/tcp | Bind mounts to shared storage. |

Document container-to-network mapping in the [Architecture Overview](../reference/architecture-overview.md).

## Docker Compose Implementation
1. Create `docker/.env` or reuse secrets store as defined in [Configuration Reference](../reference/configuration-reference.md).
2. Draft a base `docker-compose.yml`:
   ```yaml
   version: "3.9"
   services:
     opsi-db:
       image: postgres:15
       environment:
         POSTGRES_DB: opsi_db
         POSTGRES_USER: ${OPSI_DB_USER}
         POSTGRES_PASSWORD: ${OPSI_DB_PASSWORD}
       volumes:
         - opsi_db_data:/var/lib/postgresql/data
       networks:
         - opsi-backend

     opsi-server:
       build: ./services/server
       env_file:
         - ./opsi.env
       depends_on:
         - opsi-db
       ports:
         - "4447:4447"
         - "8443:8443"
       volumes:
         - opsi_repo:/var/lib/opsi
         - opsi_logs:/var/log/opsi
       networks:
         - opsi-backend
         - opsi-front
   networks:
     opsi-backend:
       driver: bridge
     opsi-front:
       driver: bridge
   volumes:
     opsi_db_data:
     opsi_repo:
     opsi_logs:
   ```
3. Validate configuration syntax with `docker compose config`.
4. Store the compose file in Git and protect secrets by referencing environment variables instead of embedding passwords.

## Networking Considerations
- **Bridged vs Host Networking:** Use host networking for PXE/TFTP if the container requires raw access to DHCP broadcasts.
- **TLS Termination:** Deploy a reverse proxy (Traefik, Nginx) within the compose stack to centralize TLS certificates.
- **Service Discovery:** Configure container names as DNS records or integrate with an external DNS server to resolve `opsi-server` from clients.

## Secrets Management Patterns
- Store credentials in `.env` files owned by root (`chmod 600`) or leverage Docker secrets.
- Rotate secrets during the [Maintenance Checklist](../operations/maintenance-checklist.md#credential-rotation) cycle.

## Validation Checklist
- [ ] `docker info` shows the correct storage driver and cgroup version.
- [ ] `docker compose up -d opsi-db` starts without errors and creates the expected volume.
- [ ] Network connectivity validated via `docker exec opsi-server ping opsi-db` (after containers are running).
- [ ] Secrets referenced in compose render correctly via `docker compose config`.

Proceed to [OPSI Server Installation](03-opsi-server-installation.md) once the platform is in place.
