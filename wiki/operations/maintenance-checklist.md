# Maintenance Checklist

Use this checklist during weekly, monthly, and quarterly maintenance windows to keep OpsiSuit healthy and compliant.

## Weekly Tasks
- Review monitoring alerts and investigate anomalies.
- Validate that nightly backups completed and transferred off-site.
- Check disk utilization (`df -h`, `docker system df`) and prune unused images if required.
- Ensure recent deployments report success; remediate failures promptly.

## Monthly Tasks
- Patch host OS and container base images; redeploy services.
- Audit OPSI package repository for stale versions and archive as needed.
- Update documentation in this wiki with any process changes.
- Perform [credential rotation](#credential-rotation) for service accounts when mandated.

## Quarterly Tasks
- Conduct full disaster recovery drill using the latest backups.
- Review capacity planning metrics and adjust resource allocations.
- Evaluate new OPSI releases and schedule [upgrade orchestration](#upgrade-orchestration).
- Perform security review of firewall rules and network segmentation.

## Credential Rotation
1. Generate new secrets/tokens in the organization’s vault.
2. Update Docker secrets or `.env` files following the [Configuration Reference](../reference/configuration-reference.md#secrets-management-patterns).
3. Redeploy affected services (`docker compose up -d <service>`).
4. Verify clients can still authenticate.
5. Document rotation in change log.

## Upgrade Orchestration
1. Review release notes and impact assessments.
2. Clone staging environment and apply upgrade following setup guides.
3. Run regression tests (agent check-in, deployment, PXE boot).
4. Schedule production upgrade window and notify stakeholders.
5. Execute upgrade with rollback plan and capture metrics before/after.

## Record Keeping
- Maintain maintenance logs in internal ticketing system.
- Attach monitoring screenshots or reports for audit trails.
- Cross-reference tasks with compliance requirements (e.g., ISO 27001, SOC 2).
