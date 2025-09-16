# Quick Installation of Prerequisites

The following quick guides show how to install the packages listed in the README
(`docker`, `docker compose`, `curl`, `git`) on common distributions. All examples
assume `sudo` privileges.

> **Note:** After adding yourself to the `docker` group you need a new terminal
> session (or log out and back in) so that the permissions take effect.

## Debian / Ubuntu / Derivatives

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

## Verify the Installation

```bash
docker --version
docker compose version
curl --version
git --version
```

If all commands print a version number, the prerequisites are satisfied.
