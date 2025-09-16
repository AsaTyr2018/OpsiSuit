# Agent: OpsiSuit

## Überblick

**Name:** OpsiSuit  
**Zweck:** Automatisierte Einrichtung und Verwaltung einer vollständigen OPSI‑Infrastructure (OS‑Deployment, Applikationsdeployment, Inventarisierung).  
**Zielplattform:** Linux‑Server (am besten Debian / Ubuntu / CentOS / RHEL etc.), möglichst unter Docker oder mittels Containerisierung.  

OpsiSuit übernimmt:

- Installation und Konfiguration des Opsi‑Servers und aller zugehörigen Komponenten  
- Einrichtung von Opsi‑Clients / Agenten auf Zielrechnern  
- Verwaltung von App‑Deployments  
- OS‑Deployment (Installation, Imaging, Partitionierung etc.)  
- Inventarisierung: Hardware, Software, Konfiguration  

---

## Komponenten & Architektur

| Komponente | Beschreibung |
|------------|--------------|
| **Opsi Server** | Zentrale Komponente, steuert Deployment, Inventarisierung, Clients. |
| **Database** | z. B. MariaDB / MySQL / PostgreSQL zur Speicherung von Opsi‑Daten. |
| **Web Frontend / Management UI** | Weboberfläche zur Verwaltung von Images, Paketen, Clients etc. |
| **Tftp / PXE + Netboot Komponenten** | Für OS‑Deployment über Netzwerk, Boot images etc. |
| **Package Repo / Paketmanagement** | Stores für Softwarepakete, Updates etc. |
| **Client‑Agent** | Wird auf Zielmaschinen installiert, führt Deployment, Inventarisierung etc. aus. |
| **Inventarisierung Modul** | Script / Agent, der Hardware‑ & Softwaredaten sammelt und zurückmeldet. |

Wenn möglich, alles in Containern betrieben, mit klarer Trennung z. B. Datenbank, Webfrontend, PXE/TFTP, Agent etc.  

---

## Installations‑ und Setupablauf

1. **Servervorbereitung**  
   - Linux‑Server mit minimaler Installation  
   - Basis‑Pakete: Docker / Docker‑Compose (oder Podman), Git, Curl, ggf. Firewall / Netzkonfiguration  
   - Netzwerk vorbereiten (z. B. DHCP + PXE, statische IP etc.), DNS falls benötigt  

2. **Containerisierte Komponenten (falls Docker verwendet wird)**  
   - Definieren von Docker‑Compose / Stack: Services für Opsi Backend, Datenbank, Web Frontend, PXE/TFTP, ggf. Proxy/Load Balancer  
   - Persistente Volumes konfigurieren (z. B. DB Daten, Logs, Images)  
   - Netzwerke und Ports (z. B. HTTP/HTTPS, TFTP, DHCP etc.)  

3. **OPSI Server Installation & Konfiguration**  
   - OPSI Paketquelle hinzufügen  
   - Installation der OPSI Server Komponenten  
   - Einrichtung Datenbank (Schema, Nutzer, Berechtigungen)  
   - Web UI konfigurieren, SSL (z. B. mittels Let’s Encrypt)  

4. **PXE / Netboot Setup**  
   - TFTP / DHCP-Konfiguration (sofern nicht bereits vorhanden)  
   - Netboot‑Images vorbereiten  
   - Boot‑Konfiguration (z. B. Linux Kernel + Initrd)  

5. **Client Agent Setup**  
   - Automatisches Ausrollen des Agenten auf Zielrechner (z. B. via SSH, via OPSI selbst)  
   - Sicherstellung, dass Inventarisierungs‑Modul läuft und regelmäßig Daten an Server sendet  

6. **App‑ und OS Deployment Setup**  
   - Definition von OS Images (Konfiguration, Partitionierung, Treiber etc.)  
   - App Paket‑Repos (Windows / Linux Applikationen)  
   - Deployment Scripts / Tasks definieren  
   - Rollout / Update Management  

7. **Inventarisierung**  
   - Erfassen von Hardwaredaten (CPU, RAM, Festplatten, Netzwerkkarten etc.)  
   - Erfassen von installierter Software & Versionen  
   - Logik zur Erkennung von Abweichungen / fehlenden Updates  

8. **Monitoring & Backup**  
   - Logsammlung, Monitoring der Dienste (z. B. via Prometheus, Grafana oder simpler Überwachung)  
   - Backup der Datenbank, der Konfiguration, der Images  

---

## Stilrichtlinien & Best Practices für den Agenten

- **Idempotenz:** Aktionen mehrfach ausgeführt erzeugen keinen Fehlerzustand.  
- **Konfigurierbarkeit:** Möglichst viele Parameter extern (z. .ENV, YAML, etc.) einstellbar: Ports, Pfade, Datenbank‑Credentials, Netzwerk etc.  
- **Modularität:** Jeder Teil (DB, Web UI, PXE, Agent, Inventarisierung) möglichst isoliert, austauschbar.  
- **Sicherheit:**  
  - SSL/TLS für Webinterfaces  
  - sichere Credentials, ggf. Secrets Management  
  - eingeschränkter Zugang zu PXE/TFTP etc.  
- **Logging & Fehlerbehandlung:** Klare Logs, verständliche Fehlermeldungen, Recovery‑Pfade.  
- **Dokumentation & Testing:** Jede Komponente sollte dokumentiert sein (Setup, Nutzung), automatische Tests / Validierungen sofern möglich.  

---

## Technische Hinweise & Defaults

- **Betriebssysteme (Server):** Debian 12 / Ubuntu LTS / CentOS / RockyLinux  
- **Datenbank:** MariaDB oder PostgreSQL, Standby oder Replikation optional  
- **Container Orchestrierung:** Docker + Docker‑Compose, optional Kubernetes in großen Setups  
- **Web UI:** Vorzugsweise der standardmäßige Opsi Webinstaller / Opsi ConfigAPI, ggf. eigenes Dashboard  
- **Netzwerkdienste:**  
  - DHCP Server oder Interaktion mit existierendem DHCP  
  - PXE/TFTP über UDP Port 69 + entsprechende Ports  
  - HTTP/HTTPS für Datei‑ und Paketbereitstellung  
- **Agenten:** Unterstützt Windows und Linux Clients  
- **Inventarisierungstakt:** z. B. tägliches Inventar, bei großen Umgebungen ggf. stündlich oder nach Bedarf  

---

## Vorschlag für Ordnerstruktur / Repository

Eine mögliche Struktur in einem Git‑Repository:

```

opsisuit/
├── docker/
│   ├── docker-compose.yml
│   ├── .env.sample
│   └── services/
│       ├── server/
│       ├── webui/
│       ├── db/
│       ├── pxe/
│       └── agent/
├── configs/
│   ├── opsi.conf
│   ├── pxe/
│   └── client\_agent.conf
├── scripts/
│   ├── setup\_server.sh
│   ├── setup\_agent.sh
│   └── inventory\_collector.sh
├── images/
│   └── os\_templates/
├── docs/
│   ├── installation.md
│   ├── usage.md
│   └── troubleshooting.md
└── tests/
├── ci\_tests/
└── integration\_tests/

````

---

## Schnittstellen & API

- **ConfigAPI** von Opsi nutzen für automatisierte Steuerung (Pakete, Clients, Aufgaben).  
- REST‑API endpoint im Agenten, um Inventarisierungsdaten zu liefern.  
- Falls nötig Webhooks oder Events für Statusänderungen oder Fehler.  

---

## Beispiel Konfigurationsvariablen (ENV / YAML)

```yaml
server:
  hostname: "opsi.example.com"
  ip: "192.168.1.10"

database:
  type: "postgresql"
  host: "db"
  port: 5432
  user: "opsiuser"
  password: "securepassword"
  dbname: "opsi_db"

pxe:
  tftp_root: "/var/lib/tftpboot"
  dhcp_conf: "/etc/dhcp/dhcpd.conf"
  pxe_images_dir: "/pxe_images"

agent:
  poll_interval_minutes: 60
  secret_key: "some_long_secret"

webui:
  port: 443
  ssl_cert: "/etc/letsencrypt/live/opsi.pem"
  ssl_key: "/etc/letsencrypt/live/opsi-key.pem"
````

---

## Aufgaben / User Stories

Damit der Agent aussagekräftig entwickelt werden kann, ein paar User Stories:

* Als Administrator möchte ich mit einem einzigen Kommando den kompletten OPSI‑Server im Docker‑Setup aufsetzen.
* Als Administrator will ich neue Clients automatisch inventarisieren können, sobald sie im Netzwerk sind.
* Als Administrator möchte ich OS Images definieren und auf neue Maschinen deployen können.
* Als Administrator will ich Applikationen auf Clients ausrollen und Updates steuern können.
* Als Administrator möchte ich Zugriff auf Logs / Status‑Views über eine Web UI haben.

---

## Zusammenfassung

OpsiSuit soll eine **vollständige, modulare, automatisierte Lösung** sein, mit der man schnell eine OPSI‑Infrastruktur auf Linux (ideal Docker) aufsetzen kann, OS & App Deployment steuern sowie Inventarisierung betreiben. Sicherheit, Konfigurierbarkeit und Wartbarkeit sind Kernelemente.


