# Client Agent Lifecycle

| Goal | Automate rollout, configuration, and maintenance of OPSI client agents across endpoints. |
| --- | --- |
| Prerequisites | OPSI server reachable, PXE services validated, admin credentials available. |
| Deliverables | Agent deployment workflows, enrollment automation, policy enforcement strategy. |

## Bootstrap and Enrolment
1. **Discovery:** Import hardware inventory from CMDB or perform network scan to identify targets.
2. **Credential Distribution:** Use temporary bootstrap credentials or SSH keys managed via secrets manager.
3. **Automated Installer:**
   ```bash
   ssh admin@client "curl -fsSL https://opsi.example.com/agent/install.sh | sudo bash"
   ```
4. **Enrollment Validation:** The agent should register with the ConfigAPI and appear under `opsi-admin -d client list`.
5. **Tagging:** Assign groups (e.g., `prod`, `lab`, `retail`) for targeted deployments.

## Configuration Policy
- **Central Policy Store:** Manage configurations via OPSI product properties and host parameters.
- **Baseline Profiles:** Define default software sets, power policies, and compliance rules per client group.
- **Scripted Tasks:** Leverage `opsi-admin -d task setProductActionRequest` to queue installations.
- **Secrets Handling:** Agents retrieve tokens from secure endpoints using short-lived certificates.

## Update & Repair Strategy
- Schedule nightly check-ins where agents request new assignments.
- Enable self-healing by pushing scripts that verify critical services and reinstall if missing.
- Use wake-on-LAN integration for off-hours patching.

## Health Monitoring
- Collect status metrics (last seen time, assignment results) and forward to monitoring system.
- Trigger alerts if agents miss two consecutive reporting intervals defined in [Inventory Scheduling](07-inventory-compliance.md#inventory-scheduling).

## Validation Checklist
- [ ] Sample client enrolls successfully and receives group tags.
- [ ] Automated installer handles retries and idempotent re-runs.
- [ ] Agent status visible in OPSI UI and via API queries.
- [ ] Secrets rotated after bootstrap completion.
- [ ] Documentation updated with enrollment SOPs in the internal runbook.

Continue with [Deployment Management](06-deployment-management.md).
