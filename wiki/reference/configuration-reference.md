# Configuration & Environment Variables

## Purpose
Central location for all configuration toggles, environment variables, and file-based settings used across OpsiSuit deployments.

## Environment Variables
| Variable | Description | Default | Notes |
| --- | --- | --- | --- |
| `OPSI_DB_HOST` | Database hostname | `opsi-db` | Match docker service name or external endpoint. |
| `OPSI_DB_PORT` | Database port | `5432` | Use `3306` for MySQL/MariaDB. |
| `OPSI_DB_USER` | Database user | — | Store in secrets manager. |
| `OPSI_DB_PASSWORD` | Database password | — | Pull at runtime via Docker secrets. |
| `OPSI_DEPOT_ID` | Depot identifier | `opsi-depot-01` | Unique per deployment. |
| `OPSI_ADMIN_TOKEN` | API access token | — | Rotate quarterly. |
| `PXE_HTTP_URL` | URL serving boot images | `https://opsi.example.com/boot` | Used by PXE templates. |
| `REPO_MIRROR_URLS` | Comma-separated remote depots | — | For replication scripts. |

## Configuration Files
| File | Location | Key Settings |
| --- | --- | --- |
| `opsi.conf` | `/etc/opsi/opsi.conf` | Backend type, logging, depot ID. |
| `opsiconfd.conf` | `/etc/opsi/opsiconfd.conf` | Worker counts, SSL certificate paths. |
| `backendManager/dispatch.conf` | `/etc/opsi/backends/dispatch.conf` | Backend routing for multi-depot setups. |
| `opsiclientd.conf` | Client side | Poll interval, script execution policies. |
| `pxelinux.cfg/*` | TFTP root | Boot menu entries per OS. |

## Secrets Management Patterns
- **.env Files:** Store non-sensitive defaults in `docker/.env`. Keep secrets in `.env.local` and exclude from Git.
- **Docker Secrets:**
  ```bash
  printf "${OPSI_DB_PASSWORD}" | docker secret create opsi_db_password -
  ```
  Reference with `secrets:` block in compose files.
- **External Vault:** Integrate with HashiCorp Vault or AWS Secrets Manager for automatic rotation.
- **Access Controls:** Limit read permissions to deployment automation accounts.

## Configuration Change Workflow
1. Modify configuration in Git branch.
2. Run automated tests or dry runs (`docker compose config`).
3. Submit change for peer review.
4. Deploy via CI/CD pipeline with rollback plan.

## Troubleshooting Tips
- Use `opsi-admin -d config get` to list current server-side settings.
- Compare container environment variables with `docker inspect <container> --format '{{json .Config.Env}}'`.
- Validate syntax using `opsi-setup --check` before restarting services.

Cross-reference the [Maintenance Checklist](../operations/maintenance-checklist.md) for configuration review cadence.
