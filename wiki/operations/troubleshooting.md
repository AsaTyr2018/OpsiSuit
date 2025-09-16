# Troubleshooting Guide

When issues arise, use this guide to triage, diagnose, and resolve problems quickly.

## Diagnostic Workflow
1. **Define the Scope:** Identify affected clients/services and timeframe.
2. **Collect Logs:**
   ```bash
   docker compose logs opsi-server
   docker compose logs opsi-pxe
   ```
3. **Check Health Dashboards:** Reference metrics defined in [Monitoring, Backup & DR](../setup/08-monitoring-backup.md#health-and-availability-checks).
4. **Reproduce:** Attempt to replicate issue in staging to observe behaviour safely.

## Common Issues
### Deployment Fails Midway
- Verify repository accessibility (`curl -I https://opsi.example.com/packages/...`).
- Confirm client has adequate disk space and permissions.
- Check OPSI product logs located on the client under `%ProgramFiles%\opsi.org\log`. 

### PXE Boot Timeout
- Ensure DHCP options 66/67 or proxy DHCP responses reach the client.
- Validate TFTP service (`tftp <server> -c get pxelinux.0`).
- Inspect firewall rules for blocked UDP ports.

### Agent Not Reporting
- Confirm `opsiclientd` service is running on the endpoint.
- Rotate authentication token if revoked; see [Client Agent Lifecycle](../setup/05-client-agents.md#bootstrap-and-enrolment).
- Inspect connectivity: `telnet opsi.example.com 4447` or equivalent.

### Database Connection Errors
- Test connectivity from OPSI server: `psql -h opsi-db -U opsi_admin opsi_db`.
- Check database container logs for resource exhaustion.
- Review secrets for expired credentials, rotate if necessary.

## Escalation
- If unresolved within SLA, escalate to platform engineering team with collected diagnostics.
- Include timeline, impact assessment, mitigation steps, and next actions.

## Post-Incident Review
- Conduct blameless retrospective.
- Update runbooks and, if required, add new monitoring checks.
- Log lessons learned in this wiki for future reference.
