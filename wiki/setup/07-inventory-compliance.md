# Inventory & Compliance

| Goal | Collect accurate hardware/software inventory and enforce compliance baselines across all managed clients. |
| --- | --- |
| Prerequisites | Client agents reporting successfully, database backups configured. |
| Deliverables | Inventory schedule, compliance policies, reporting dashboards. |

## Inventory Scheduling
- **Frequency:** Default to daily scans; increase to hourly for high-risk segments.
- **Trigger Methods:** Combine scheduled tasks with event-based scans (e.g., on login, on new hardware detection).
- **Performance Tuning:** Throttle concurrent scans by staggering start times; monitor database load.
- **Data Retention:** Archive historical snapshots beyond 12 months to cold storage.

## Data Collection Scope
| Category | Data Points | Source |
| --- | --- | --- |
| Hardware | CPU, RAM, disks, BIOS/UEFI, peripherals | OPSI hardware inventory module |
| Software | Installed packages, version, install date | OPSI localboot products |
| Compliance | Patch level, antivirus state, encryption status | Custom scripts, OS queries |
| Network | MAC/IP, VLAN, Wi-Fi SSID | Agent network probes |

## Compliance Policies
1. **Baseline Definitions:** Document security standards (e.g., BitLocker required, specific antivirus versions).
2. **Policy Enforcement:** Use OPSI product actions to remediate non-compliance (install patch, enable service).
3. **Exception Handling:** Track approved deviations with expiration dates in ITSM.
4. **Reporting:** Integrate with BI tooling (Grafana, Power BI) pulling from OPSI database views.

## Dashboards & Alerts
- Build Grafana dashboards showing compliance rates per business unit.
- Trigger alerts when compliance falls below thresholds using Prometheus alert rules.
- Provide self-service reports to stakeholders via web UI.

## Validation Checklist
- [ ] Inventory jobs complete within defined time window.
- [ ] Compliance dashboard refreshed with latest data.
- [ ] Exceptions reviewed monthly and expired ones closed.
- [ ] Non-compliant clients trigger automated remediation tasks.
- [ ] Audit exports stored securely for external reviews.

Next up: [Monitoring, Backup & DR](08-monitoring-backup.md).
