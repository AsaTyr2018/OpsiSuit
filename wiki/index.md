# OpsiSuit Wiki

Welcome to the living knowledge base for **OpsiSuit**, the automated toolkit for deploying and operating an OPSI infrastructure. This wiki is organized so you can trace every function of the setup process, understand the architectural building blocks, and keep day-to-day operations running smoothly.

## How to Use This Wiki
- **Follow the setup path** if you are bootstrapping a new environment. Each step links to an in-depth guide that explains objectives, inputs, and outputs.
- **Jump to reference pages** when you need reusable snippets such as environment variables, component duties, or glossary terms.
- **Consult the operations playbooks** for recurring maintenance, monitoring, and troubleshooting routines.

## Navigation

### Setup Guides
1. [Server Preparation](setup/01-server-preparation.md)
2. [Container Platform & Topology](setup/02-container-platform.md)
3. [OPSI Server Installation](setup/03-opsi-server-installation.md)
4. [PXE & Netboot Services](setup/04-pxe-netboot.md)
5. [Client Agent Lifecycle](setup/05-client-agents.md)
6. [Deployment Management](setup/06-deployment-management.md)
7. [Inventory & Compliance](setup/07-inventory-compliance.md)
8. [Monitoring, Backup & DR](setup/08-monitoring-backup.md)

### Reference Library
- [Architecture Overview](reference/architecture-overview.md)
- [Configuration & Environment Variables](reference/configuration-reference.md)
- [Glossary & Concept Index](reference/glossary.md)

### Operations & Governance
- [Maintenance Checklist](operations/maintenance-checklist.md)
- [Troubleshooting Guide](operations/troubleshooting.md)

## Setup Process Map
```mermaid
flowchart LR
    A(Server Preparation) --> B(Container Platform)
    B --> C(OPSI Server Install)
    C --> D(PXE & Netboot)
    D --> E(Client Agents)
    E --> F(Deployment Management)
    F --> G(Inventory & Compliance)
    G --> H(Monitoring & Backup)
```
Use the map above as the canonical order for executing the setup. Each node corresponds to a detailed guide describing the **purpose**, **required artefacts**, **key actions**, and **validation checks** for that phase.

## Searchable Index
Use this index to quickly locate the guide that covers a specific concept or function. Each keyword is hyperlinked to the most relevant section.

| Keyword | Description | Primary Location |
| --- | --- | --- |
| Access control | Managing user accounts, roles, and API credentials for OPSI services. | [Monitoring, Backup & DR](setup/08-monitoring-backup.md#security-hardening--access-control) |
| Agent bootstrap | Automated rollout of OPSI agents to clients, including credential exchange. | [Client Agent Lifecycle](setup/05-client-agents.md#bootstrap-and-enrolment) |
| Application packages | Building, signing, and distributing OPSI software packages. | [Deployment Management](setup/06-deployment-management.md#application-package-workflow) |
| Backup rotation | Scheduling and validating recurring data backups. | [Monitoring, Backup & DR](setup/08-monitoring-backup.md#backup-rotation-and-disaster-recovery) |
| Certificates | Provisioning and renewing TLS certificates for secure endpoints. | [OPSI Server Installation](setup/03-opsi-server-installation.md#secure-the-configapi--web-ui) |
| DHCP relay | Integrating OPSI PXE boot with existing DHCP infrastructure. | [PXE & Netboot Services](setup/04-pxe-netboot.md#dhcp-integration-options) |
| Docker Compose | Orchestrating services with compose files, volumes, and secrets. | [Container Platform & Topology](setup/02-container-platform.md#docker-compose-implementation) |
| Health checks | Defining probes and telemetry to track service status. | [Monitoring, Backup & DR](setup/08-monitoring-backup.md#health-and-availability-checks) |
| Inventory schedule | Frequency and automation of hardware/software scans. | [Inventory & Compliance](setup/07-inventory-compliance.md#inventory-scheduling) |
| Network planning | IP addressing, VLANs, firewalls, and DNS preparation tasks. | [Server Preparation](setup/01-server-preparation.md#network-foundation) |
| Netboot images | Building and curating PXE-compatible boot images. | [PXE & Netboot Services](setup/04-pxe-netboot.md#netboot-image-workflow) |
| Package repository | Structuring storage and synchronization of OPSI packages. | [Deployment Management](setup/06-deployment-management.md#repository-structure) |
| Secrets management | Handling sensitive data in `.env` files or secret stores. | [Configuration & Environment Variables](reference/configuration-reference.md#secrets-management-patterns) |
| Service topology | Logical overview of OPSI server, database, PXE, and agents. | [Architecture Overview](reference/architecture-overview.md#service-topology) |
| Storage planning | Calculating disk and object storage requirements. | [Server Preparation](setup/01-server-preparation.md#storage-planning) |
| Upgrade orchestration | Sequencing updates across OPSI components. | [Maintenance Checklist](operations/maintenance-checklist.md#upgrade-orchestration) |

> **Tip:** Use the built-in search (press `/` on GitHub) to locate keywords, or browse by category above. Each document begins with a summary table that makes scanning faster.

## Document Conventions
- Command snippets assume a Debian/Ubuntu host unless explicitly stated.
- Environment variables are written as `UPPER_SNAKE_CASE` and referenced in the [configuration reference](reference/configuration-reference.md).
- Each setup guide concludes with validation checks ensuring the step completed successfully.

Happy building!
