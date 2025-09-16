# Monitoring, Backup & DR

| Goal | Establish observability, backup, and disaster recovery practices for the OpsiSuit platform. |
| --- | --- |
| Prerequisites | OPSI services in production, monitoring stack available, backup storage configured. |
| Deliverables | Monitoring dashboards, alert policies, backup rotation plan, documented recovery procedures. |

## Health and Availability Checks
- **Service Probes:** Implement HTTP(S) health checks for ConfigAPI, web UI, and repository endpoints.
- **Synthetic Transactions:** Schedule periodic API calls that perform read/write operations to verify end-to-end functionality.
- **Resource Monitoring:** Track CPU, memory, disk I/O, and network throughput using Prometheus or equivalent.
- **Log Aggregation:** Centralize logs (OPSIconfd, PXE, database) and set anomaly detection alerts.

## Backup Rotation and Disaster Recovery
1. **Database Backups:**
   ```bash
   pg_dump -h opsi-db -U ${OPSI_DB_USER} opsi_db | gzip > /backups/opsi-db-$(date +%F).sql.gz
   ```
   Automate with cron and store in encrypted off-site storage.
2. **Repository Snapshots:** Use `rsync --delete` or snapshot-capable storage (ZFS/Btrfs) for package repositories.
3. **Configuration Archives:** Version control config files and export environment variables securely.
4. **Rotation Policy:** Retain daily backups for 14 days, weekly for 8 weeks, monthly for 12 months.
5. **Recovery Drills:** Conduct bi-annual restore tests and document outcomes.

## Security Hardening & Access Control
- Enforce least-privilege roles within OPSI and underlying database.
- Rotate API tokens and SSH keys per the [Maintenance Checklist](../operations/maintenance-checklist.md#credential-rotation).
- Enable MFA on management interfaces when available.
- Audit logs quarterly to verify access compliance.

## Incident Response
- Maintain a runbook with escalation contacts and communication templates.
- Integrate monitoring alerts with on-call platform (PagerDuty, Opsgenie).
- Document decision trees for failover vs. restore scenarios.

## Validation Checklist
- [ ] Monitoring dashboards display live metrics for all core services.
- [ ] Alert rules tested and confirmed to notify on-call rotation.
- [ ] Latest backup restore tested successfully in staging.
- [ ] Access review completed and documented.
- [ ] Disaster recovery plan approved by stakeholders.

You have now completed the setup journey. Continue to the [Maintenance Checklist](../operations/maintenance-checklist.md) for ongoing operations.
