# OpsiSuit

OpsiSuit soll eine automatisierte, containerisierte OPSI-Infrastruktur aufbauen. Das
Projekt bündelt die notwendigen Komponenten (OPSI-Server, Datenbank, PXE/TFTP und
Agenten-Konfiguration) und liefert ein Installationsskript, das den ersten Aufbau
vereinfachen soll.

## Aktueller Stand

- Initiale Repository-Struktur mit Docker Compose Stack.
- Beispielkonfigurationen für OPSI-Server, PXE/TFTP und Client-Agent.
- Installer-Skript (`scripts/opsisuit-installer.sh`), das Abhängigkeiten prüft,
  Konfigurationsdateien bereitstellt und den Compose-Stack starten kann.

## Komponenten im Compose-Stack

| Service       | Beschreibung                                                                 |
|---------------|------------------------------------------------------------------------------|
| `db`          | MariaDB 10.11 als zentrales Backend für OPSI.                                |
| `redis`       | Redis 7 als In-Memory-Cache und Message-Broker für den OPSI-Server.          |
| `opsi-server` | OPSI-Server inklusive Config-API und Depot. Greift auf DB und Konfigurationen zu. |
| `pxe`         | netboot.xyz TFTP/HTTP-Service mit Webinterface (Standard: `netbootxyz/netbootxyz`). |

## Repository-Struktur

```
.
├── configs/                # Beispiel- und Zielkonfigurationen
│   ├── agent/
│   ├── opsi/
│   └── pxe/
├── docker/
│   ├── .env.example        # Beispielwerte für den Compose-Stack
│   └── docker-compose.yml
├── scripts/
│   └── opsisuit-installer.sh
└── README.md
```

Die tatsächlichen Konfigurationsdateien ohne `.example` werden vom Installer
gelegt und sind per `.gitignore` vom Repository ausgeschlossen.

## Voraussetzungen

- Linux-Host (Debian/Ubuntu, RHEL/CentOS/Rocky, openSUSE oder Arch/Manjaro).
- Docker und Docker Compose (Plugin oder `docker-compose`).
- `curl` und `git`.

**Kurzinstallation (Debian/Ubuntu):**

```bash
sudo apt update
sudo apt install -y docker.io docker-compose-plugin curl git
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"
```

> Nach dem Hinzufügen zur `docker`-Gruppe ist eine neue Terminal-Sitzung nötig,
> damit die Berechtigungen greifen.

Installationshinweise für weitere Distributionen stehen in
[docs/requirements-installation.md](docs/requirements-installation.md).

Das Installer-Skript kann fehlende Pakete optional automatisch nachinstallieren.

## Installer verwenden

```bash
# Übersicht anzeigen
./scripts/opsisuit-installer.sh --help

# Vollständige Installation inkl. Start des Stacks
sudo ./scripts/opsisuit-installer.sh --auto-install-deps

# Nur Dateien vorbereiten, ohne Container zu starten
./scripts/opsisuit-installer.sh --skip-start

# Testlauf ohne Änderungen
./scripts/opsisuit-installer.sh --dry-run
```

Das Skript führt folgende Schritte aus:

1. Anlegen benötigter Verzeichnisse (`data/`, `logs/`, `backups/`, `configs/`).
2. Kopieren der `.example`-Konfigurationsdateien zu editierbaren Vorlagen.
3. Prüfen bzw. (optional) Installieren der Abhängigkeiten.
4. Start des Docker-Compose-Stacks (`docker compose up -d`).

Mit `--force-env` bzw. `--force-config` lassen sich vorhandene `.env`- bzw.
Konfigurationsdateien überschreiben.

## Konfiguration anpassen

1. `docker/.env` – zentrale Variablen für den Compose-Stack
   (Ports, Passwörter, Image-Tags, Secrets).
2. `configs/opsi/opsi.conf` – globale OPSI-Einstellungen.
3. `configs/pxe/pxe.conf` – Beispielkonfiguration für dnsmasq/TFTP.
4. `configs/agent/client-agent.conf` – Vorgaben für den OPSI-Client-Agenten.

> **Hinweis:** Für den PXE-Container (`netboot.xyz`) muss `SERVICE_UID`/`SERVICE_GID`
> auf eine reguläre Benutzer-/Gruppen-ID zeigen. Die Standardwerte (`1000`) vermeiden
> den Fehler `Invalid user name nbxyz` beim Start von `supervisord`. Passen Sie die IDs
> bei Bedarf an die UID/GID Ihres Docker-Hosts an.

Alle Dateien werden beim ersten Lauf des Installers aus den jeweiligen
`.example`-Vorlagen kopiert und können anschließend editiert werden.

## Nächste Schritte

- Ausarbeitung der OPSI-spezifischen Konfigurationswerte und Secrets.
- Ergänzung weiterer Services (z. B. Webfrontend, Monitoring, Inventarisierung).
- Automatisierte Tests und Validierung der Deployment-Schritte.
