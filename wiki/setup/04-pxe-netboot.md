# PXE & Netboot Services

| Goal | Deliver automated network boot services for OS deployment through PXE/TFTP/HTTP. |
| --- | --- |
| Prerequisites | OPSI server running, network ports reserved from [Server Preparation](01-server-preparation.md). |
| Deliverables | Configured TFTP/DHCP/HTTP services, curated boot images, documented boot menus. |

## Service Components
- **TFTP Server (`opsi-pxe`):** Serves bootloaders and kernel/initrd files.
- **HTTP/HTTPS Server:** Hosts large boot images (`.wim`, `.iso`).
- **DHCP/Proxy DHCP:** Directs clients to the OPSI PXE server.
- **Boot Menu Generator:** Dynamically builds menus per hardware profile.

## DHCP Integration Options
1. **Authoritative DHCP inside OpsiSuit:**
   - Configure `isc-dhcp-server` container with scope definitions.
   - Ensure only one authoritative DHCP server on the broadcast domain.
2. **Proxy DHCP (Recommended for existing networks):**
   - Enable `dnsmasq` in proxy mode listening on `4011/udp`.
   - Configure existing DHCP server options 66/67 to point to the PXE service.
3. **DHCP Relay:**
   - Use network equipment to forward DHCP broadcast traffic to the OPSI PXE container.
   - Document relay configuration (IP helper) for audit.

## Netboot Image Workflow
1. **Collect Sources:** Acquire vendor ISO/WIM files and drivers. Verify checksums.
2. **Build Boot Images:** Use OPSI `opsi-linux-bootimage` tooling or `winpe` for Windows.
   ```bash
   docker compose run --rm opsi-pxe opsi-mkbootimage --template winpe --arch x64 --output /srv/tftp/boot/winpe-x64
   ```
3. **Version Control:** Store build scripts in `docker/services/pxe/bootimage/` with semantic version tags.
4. **Menu Configuration:** Update `pxelinux.cfg/default` or `grub.cfg` to include new entries:
   ```cfg
   LABEL win10_install
       MENU LABEL Windows 10 Deployment
       KERNEL winpe-x64/wimboot
       INITRD winpe-x64/boot.wim
   ```
5. **Testing:** Use virtual machines (e.g., `virt-install --pxe`) to validate images before production rollout.

## HTTP Distribution
- Host large files via HTTPS to maintain integrity.
- Enable range requests to support resume (`nginx` `aio on;` `sendfile on;`).
- Offload to CDN or mirror if remote sites require faster downloads.

## Security Controls
- Restrict PXE to provisioning VLANs; block from user networks.
- Sign boot scripts where supported and store checksums for integrity audits.
- Log client MAC/IP pairs for traceability and compliance.

## Validation Checklist
- [ ] PXE server responds to `tftp` GET requests from provisioning VLAN.
- [ ] Test client obtains boot menu with correct options.
- [ ] Netboot image checksum validated against stored manifest.
- [ ] DHCP/proxy configuration reviewed and documented.
- [ ] Boot service monitoring integrated into [Monitoring, Backup & DR](08-monitoring-backup.md#health-and-availability-checks).

Next, implement the [Client Agent Lifecycle](05-client-agents.md).
