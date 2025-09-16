# Deployment Management

| Goal | Define and operate repeatable OS and application deployment pipelines through OPSI. |
| --- | --- |
| Prerequisites | OPSI server operational, client agents enrolled, package repository storage mounted. |
| Deliverables | Deployment workflows, package repository structure, change control procedures. |

## OS Deployment Workflow
1. **Template Definition:** Create OPSI products for each OS version (`win10-x64`, `ubuntu-22-lts`).
2. **Pre/Post Scripts:** Implement preflight checks (disk wipe, BIOS settings) and post-install tasks (join domain, install monitoring).
3. **Driver Management:** Store vendor drivers in `packages/drivers/<vendor>/<model>` and map via hardware detection rules.
4. **Scheduling:** Use OPSI event configuration to trigger installations during maintenance windows.
5. **Rollback:** Prepare rescue media and snapshot strategies for virtual infrastructure.

## Application Package Workflow
1. **Package Creation:**
   ```bash
   opsi-newprod -p mycorp -n chrome -V 123.0.1
   cd mycorp-chrome
   ./opsi-makepackage
   ```
2. **Signing & Integrity:** Sign packages with GPG; distribute public keys to clients.
3. **Testing:** Deploy to staging clients using dedicated host groups.
4. **Promotion:** Promote packages to production by updating assignment policies and notifying stakeholders.

## Repository Structure
Maintain a clear structure under `/var/lib/opsi/repository`:
```
repository/
├── os/
│   ├── windows/
│   └── linux/
├── apps/
│   ├── staging/
│   └── production/
└── drivers/
    └── vendor-model/
```
- Use Git LFS or object storage integration for large ISOs.
- Mirror repository content to remote depots using `rsync` or S3 replication.

## Change Control & Automation
- Integrate deployments with CI pipelines (GitHub Actions) that build packages on merge and push to repository.
- Track change requests and approvals in your ITSM tool; link to Git commits.
- Use tagging conventions (`deploy/os/win10/2024-04`) to reference release bundles.

## Validation Checklist
- [ ] New OS deployment completes end-to-end in test lab.
- [ ] Application package installs cleanly and reports success status codes.
- [ ] Repository mirrors synchronize without errors and produce checksum reports.
- [ ] Change requests documented with rollback procedures.
- [ ] Stakeholders notified via automation (chat/webhook) upon promotion.

Advance to [Inventory & Compliance](07-inventory-compliance.md).
