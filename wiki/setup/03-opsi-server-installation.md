# OPSI Server Installation

| Goal | Deploy and configure the OPSI application stack within the prepared container platform. |
| --- | --- |
| Prerequisites | Running container runtime and compose stack from [previous step](02-container-platform.md), database reachable. |
| Deliverables | OPSI server container image, initialized database schema, secured ConfigAPI and web interface. |

## Build or Pull Server Image
1. **Option A – Official Packages:** Use the OPSI vendor image and pin to a specific version tag.
   ```bash
   docker pull opsiorg/opsi-server:2024.1
   ```
2. **Option B – Custom Build:** Extend a base image for additional tooling.
   ```Dockerfile
   FROM opsiorg/opsi-server:2024.1
   RUN apt-get update && apt-get install -y vim less && rm -rf /var/lib/apt/lists/*
   ```
   Build with `docker build -t local/opsi-server:2024.1 .`.

## Database Initialization
1. Create database users:
   ```sql
   CREATE DATABASE opsi_db;
   CREATE USER opsi_admin WITH ENCRYPTED PASSWORD 'change_me';
   GRANT ALL PRIVILEGES ON DATABASE opsi_db TO opsi_admin;
   ```
2. Apply OPSI schema by running the included migration script:
   ```bash
   docker compose run --rm opsi-server opsi-setup --configure-mysql
   ```
   Substitute `--configure-postgres` if using PostgreSQL.

## Configure Core Services
- **Config Files:** Mount `configs/opsi.conf` into `/etc/opsi/opsi.conf`. Key parameters:
  - `backend`: `mysql` or `postgresql`
  - `depotId`: Unique identifier (e.g., `opsi-depot-01`)
  - `logLevel`: `4` for verbose debugging during setup, reduce after validation.
- **Admin Credentials:** Use `opsi-admin -d task setRights` to set initial administrator password and assign roles.
- **Service Registration:** Ensure the service registers with the ConfigAPI using `opsiconfd` configuration.

## Secure the ConfigAPI & Web UI
1. Generate TLS certificates (Let's Encrypt or enterprise CA). Example using `certbot`:
   ```bash
   sudo certbot certonly --standalone -d opsi.example.com
   ```
2. Mount certificates into the container and reference them in `opsiconfd.conf`:
   ```ini
   [global]
   sslServerCertFile = /etc/ssl/private/opsi.crt
   sslServerKeyFile  = /etc/ssl/private/opsi.key
   ```
3. Force HTTPS redirects in the reverse proxy and disable legacy cipher suites.
4. Enable API authentication via tokens and document credentials in the secrets manager.

## Post-Installation Tuning
- **Background Workers:** Tune worker counts (`opsiconfd workers`) according to CPU capacity.
- **Logging:** Forward logs to a central system using `rsyslog` or Fluent Bit sidecars.
- **Package Cache:** Configure `/var/lib/opsi/repository` to point to high-capacity storage defined in [Storage Planning](01-server-preparation.md#storage-planning).

## Validation Checklist
- [ ] `docker compose up -d opsi-server` completes successfully.
- [ ] `opsi-admin -d service info` returns status `running`.
- [ ] HTTPS access to `https://opsi.example.com:8443` presents a trusted certificate.
- [ ] API token authentication verified via `curl -H "Authorization: Bearer <token>" https://opsi.example.com:8443/rpc`.
- [ ] Backup of configuration files committed to the internal version control repository.

Continue with [PXE & Netboot Services](04-pxe-netboot.md).
