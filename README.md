# OpsiSuit

OpsiSuit is intended to build an automated, containerized OPSI infrastructure. The
project bundles the required components (OPSI server, database, PXE/TFTP, and
agent configuration) and provides an installation script to simplify the initial
setup.

## Current Status

- Initial repository structure with Docker Compose stack.
- Sample configurations for OPSI server, PXE/TFTP, and client agent.
- Installer script (`scripts/opsisuit-installer.sh`) that checks dependencies,
  provides configuration files, and can start the compose stack.

## Components in the Compose Stack

| Service       | Description                                                                 |
|---------------|------------------------------------------------------------------------------|
| `db`          | MariaDB 10.11 as the central backend for OPSI.                              |
| `redis`       | Redis Stack (including RedisTimeSeries) as cache and metrics backend for OPSI. |
| `opsi-server` | OPSI server including Config API and depot. Accesses the database and configurations. |
| `pxe`         | netboot.xyz TFTP/HTTP service with web interface (default: `netbootxyz/netbootxyz`). |

## Repository Structure

```
.
├── configs/                # Sample and target configurations
│   ├── agent/
│   ├── opsi/
│   └── pxe/
├── docker/
│   ├── .env.example        # Example values for the compose stack
│   └── docker-compose.yml
├── scripts/
│   └── opsisuit-installer.sh
└── README.md
```

The actual configuration files without `.example` are created by the installer
and are excluded from the repository via `.gitignore`.

## Prerequisites

- Linux host (Debian/Ubuntu, RHEL/CentOS/Rocky, openSUSE, or Arch/Manjaro).
- Docker and Docker Compose (plugin or `docker-compose`).
- `curl` and `git`.

**Quick installation (Debian/Ubuntu):**

```bash
sudo apt update
sudo apt install -y docker.io docker-compose-plugin curl git
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"
```

> After adding yourself to the `docker` group you need a new terminal session so that the permissions take effect.

Installation notes for additional distributions can be found in
[docs/requirements-installation.md](docs/requirements-installation.md).

The installer script can optionally install missing packages automatically.

## Using the Installer

```bash
# Show overview
./scripts/opsisuit-installer.sh --help

# Full installation including starting the stack
sudo ./scripts/opsisuit-installer.sh --auto-install-deps

# Only prepare files without starting containers
./scripts/opsisuit-installer.sh --skip-start

# Dry run without changes
./scripts/opsisuit-installer.sh --dry-run
```

The script performs the following steps:

1. Create required directories (`data/`, `logs/`, `backups/`, `configs/`).
2. Copy `.example` configuration files to editable templates.
3. Check and optionally install dependencies.
4. Start the Docker Compose stack (`docker compose up -d`).

Use `--force-env` or `--force-config` to overwrite existing `.env` or
configuration files.

## Adjusting the Configuration

1. `docker/.env` – central variables for the compose stack
   (ports, passwords, image tags, secrets).
2. `configs/opsi/opsi.conf` – sample snippet for global OPSI settings
   (copy to `data/opsi/etc/conf.d/` if needed).
3. `configs/pxe/pxe.conf` – sample configuration for dnsmasq/TFTP.
4. `configs/agent/client-agent.conf` – template for the OPSI client agent
   (copy to `data/opsi/etc/agent.d/` as required).

> **Persistent data storage:** When it starts, the OPSI server moves its
> directories `/etc/opsi`, `/var/lib/opsi`, `/var/log/opsi`, and
> `/var/lib/opsiconfd` into `/data` inside the container. The entire data
> directory is available on the host under `data/opsi/`. Logs are therefore
> located under `data/opsi/log/`. The folders `configs/opsi/` and
> `configs/agent/` continue to hold sample snippets that can be copied to
> `data/opsi/etc/conf.d/` or `data/opsi/etc/agent.d/` to inject custom
> settings.

> **Note:** For the PXE container (`netboot.xyz`), `SERVICE_UID`/`SERVICE_GID`
> must refer to a regular user/group ID. The default values (`1000`) prevent
> the error `Invalid user name nbxyz` when `supervisord` starts. Adjust the IDs
> to match the UID/GID of your Docker host if necessary.

> **Mission-critical defaults:** Internal communication ports such as `OPSI_API_PORT`,
> `OPSI_DEPOT_PORT`, `PXE_TFTP_PORT`, and `REDIS_SERVICE_PORT` follow fixed
> standards and are no longer queried by the installer. They are written with
> their default values into `docker/.env` so that the core services can communicate
> reliably. Exposed HTTP ports (e.g., for web UIs) remain configurable. The Redis
> connection for opsiconfd (`OPSICONFD_REDIS_URL`) is also fixed to
> `redis://redis:${REDIS_SERVICE_PORT:-6379}/0` and is no longer overwritten via `.env`.

> **FQDN required:** The OPSI server container adopts the `OPSI_SERVER_FQDN`
> defined in `.env` directly as its hostname. Always use a fully qualified domain
> name (e.g., `opsi.example.local`). Otherwise `opsiconfd` refuses to start with
> `ValueError: Bad fqdn`.

All files are copied from their respective `.example` templates during the
installer's first run and can then be edited.

## Next Steps

- Work out the OPSI-specific configuration values and secrets.
- Add additional services (e.g., web frontend, monitoring, inventory).
- Automated tests and validation of deployment steps.
