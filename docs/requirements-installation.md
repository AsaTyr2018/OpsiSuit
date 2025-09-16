# Schnellinstallation der Voraussetzungen

Die folgenden Kurz-Anleitungen zeigen, wie sich die in der README genannten
Pakete (`docker`, `docker compose`, `curl`, `git`) auf gängigen Distributionen
installieren lassen. Alle Beispiele setzen `sudo`-Rechte voraus.

> **Hinweis:** Nach dem Hinzufügen zur `docker`-Gruppe ist eine neue
> Terminal-Sitzung (oder Ab- und Anmeldung) erforderlich, damit die
> Berechtigungen greifen.

## Debian / Ubuntu / Derivate

```bash
sudo apt update
sudo apt install -y docker.io docker-compose-plugin curl git
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"
```

## RHEL / CentOS / Rocky Linux / AlmaLinux

```bash
sudo dnf install -y dnf-plugins-core curl git
sudo dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"
```

## openSUSE Leap / Tumbleweed

```bash
sudo zypper refresh
sudo zypper install -y docker docker-compose curl git
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"
```

## Arch Linux / Manjaro

```bash
sudo pacman -Syu --needed docker docker-compose curl git
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"
```

## Installation prüfen

```bash
docker --version
docker compose version
curl --version
git --version
```

Wenn alle Befehle eine Versionsnummer ausgeben, sind die Voraussetzungen erfüllt.
