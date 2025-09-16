#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCKER_DIR="${PROJECT_ROOT}/docker"
CONFIG_DIR="${PROJECT_ROOT}/configs"
DATA_DIR="${PROJECT_ROOT}/data"
LOG_DIR="${PROJECT_ROOT}/logs"
BACKUP_DIR="${PROJECT_ROOT}/backups"

ENV_TEMPLATE="${DOCKER_DIR}/.env.example"
ENV_FILE="${DOCKER_DIR}/.env"
COMPOSE_FILE="${DOCKER_DIR}/docker-compose.yml"

AUTO_INSTALL_DEPS=0
DRY_RUN=0
SKIP_START=0
FORCE_ENV=0
FORCE_CONFIG=0

PACKAGE_MANAGER=""
APT_UPDATED=0

declare -a MISSING_DEPENDENCIES=()
declare -a DOCKER_COMPOSE_CMD=()

log_info() {
  printf '[INFO] %s\n' "$*"
}

log_warn() {
  printf '[WARN] %s\n' "$*" >&2
}

log_error() {
  printf '[ERROR] %s\n' "$*" >&2
}

usage() {
  cat <<'USAGE'
OpsiSuit Installer
===================

Bootstraps the OpsiSuit Docker stack. The installer checks required
dependencies, prepares configuration files and, unless told otherwise,
starts the Docker Compose stack.

Usage: scripts/opsisuit-installer.sh [options]

Options:
  --auto-install-deps    Install missing dependencies with the detected
                         package manager (requires root).
  --dry-run              Print the actions without modifying the system.
  --skip-start           Do not start the Docker Compose stack.
  --force-env            Overwrite an existing docker/.env file with the
                         template.
  --force-config         Overwrite generated configuration files with the
                         templates in configs/.
  -h, --help             Show this help message.
USAGE
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --auto-install-deps)
        AUTO_INSTALL_DEPS=1
        ;;
      --dry-run)
        DRY_RUN=1
        ;;
      --skip-start)
        SKIP_START=1
        ;;
      --force-env)
        FORCE_ENV=1
        ;;
      --force-config)
        FORCE_CONFIG=1
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        log_error "Unknown option: $1"
        usage
        exit 1
        ;;
    esac
    shift
  done
}

ensure_directory() {
  local dir="$1"
  if [[ -d "$dir" ]]; then
    log_info "Directory $dir already exists"
    return
  fi

  if (( DRY_RUN )); then
    log_info "[dry-run] Would create directory $dir"
  else
    mkdir -p "$dir"
    log_info "Created directory $dir"
  fi
}

ensure_directories() {
  local dirs=(
    "$DATA_DIR"
    "$DATA_DIR/db"
    "$DATA_DIR/opsi"
    "$DATA_DIR/pxe"
    "$LOG_DIR"
    "$LOG_DIR/opsi-server"
    "$BACKUP_DIR"
    "$CONFIG_DIR"
    "$CONFIG_DIR/opsi"
    "$CONFIG_DIR/pxe"
    "$CONFIG_DIR/agent"
  )

  for dir in "${dirs[@]}"; do
    ensure_directory "$dir"
  done
}

copy_template() {
  local template="$1"
  local destination="$2"
  local force=$3

  if [[ ! -f "$template" ]]; then
    log_warn "Template $template is missing; skipping"
    return
  fi

  if [[ -f "$destination" && $force -eq 0 ]]; then
    log_info "File $destination already exists; skipping"
    return
  fi

  if (( DRY_RUN )); then
    log_info "[dry-run] Would copy $template to $destination"
  else
    cp "$template" "$destination"
    log_info "Provisioned $destination from template"
  fi
}

ensure_env_file() {
  if [[ ! -f "$ENV_TEMPLATE" ]]; then
    log_error "Environment template $ENV_TEMPLATE not found"
    exit 1
  fi

  copy_template "$ENV_TEMPLATE" "$ENV_FILE" "$FORCE_ENV"
}

ensure_config_templates() {
  copy_template "$CONFIG_DIR/opsi/opsi.conf.example" "$CONFIG_DIR/opsi/opsi.conf" "$FORCE_CONFIG"
  copy_template "$CONFIG_DIR/pxe/pxe.conf.example" "$CONFIG_DIR/pxe/pxe.conf" "$FORCE_CONFIG"
  copy_template "$CONFIG_DIR/agent/client-agent.conf.example" "$CONFIG_DIR/agent/client-agent.conf" "$FORCE_CONFIG"
}

detect_package_manager() {
  if [[ -n "$PACKAGE_MANAGER" ]]; then
    return 0
  fi

  if command -v apt-get >/dev/null 2>&1; then
    PACKAGE_MANAGER="apt"
  elif command -v dnf >/dev/null 2>&1; then
    PACKAGE_MANAGER="dnf"
  elif command -v yum >/dev/null 2>&1; then
    PACKAGE_MANAGER="yum"
  elif command -v zypper >/dev/null 2>&1; then
    PACKAGE_MANAGER="zypper"
  elif command -v pacman >/dev/null 2>&1; then
    PACKAGE_MANAGER="pacman"
  else
    return 1
  fi

  return 0
}

install_packages() {
  local packages=("$@")
  if (( ${#packages[@]} == 0 )); then
    return 0
  fi

  if ! detect_package_manager; then
    log_error "Unable to detect package manager to install: ${packages[*]}"
    return 1
  fi

  if (( DRY_RUN )); then
    log_info "[dry-run] Would install packages with $PACKAGE_MANAGER: ${packages[*]}"
    return 0
  fi

  if [[ $EUID -ne 0 ]]; then
    log_error "Installing packages requires root privileges"
    return 1
  fi

  case "$PACKAGE_MANAGER" in
    apt)
      if (( APT_UPDATED == 0 )); then
        log_info "Updating apt package index..."
        DEBIAN_FRONTEND=noninteractive apt-get update
        APT_UPDATED=1
      fi
      log_info "Installing packages with apt: ${packages[*]}"
      DEBIAN_FRONTEND=noninteractive apt-get install -y "${packages[@]}"
      ;;
    dnf)
      log_info "Installing packages with dnf: ${packages[*]}"
      dnf install -y "${packages[@]}"
      ;;
    yum)
      log_info "Installing packages with yum: ${packages[*]}"
      yum install -y "${packages[@]}"
      ;;
    zypper)
      log_info "Installing packages with zypper: ${packages[*]}"
      zypper --non-interactive install "${packages[@]}"
      ;;
    pacman)
      log_info "Installing packages with pacman: ${packages[*]}"
      pacman -Sy --noconfirm "${packages[@]}"
      ;;
    *)
      log_error "Unsupported package manager: $PACKAGE_MANAGER"
      return 1
      ;;
  esac
}

ensure_command() {
  local command="$1"
  local package_name="${2:-$1}"

  if command -v "$command" >/dev/null 2>&1; then
    log_info "$command already present"
    return 0
  fi

  log_warn "$command not found"
  if (( AUTO_INSTALL_DEPS )); then
    if install_packages "$package_name"; then
      if command -v "$command" >/dev/null 2>&1; then
        log_info "$command installed successfully"
        return 0
      fi
    fi
    log_error "Failed to install $command automatically"
    return 1
  else
    MISSING_DEPENDENCIES+=("$command")
    return 1
  fi
}

set_docker_compose_cmd() {
  if docker compose version >/dev/null 2>&1; then
    DOCKER_COMPOSE_CMD=(docker compose)
    return 0
  fi

  if command -v docker-compose >/dev/null 2>&1; then
    DOCKER_COMPOSE_CMD=(docker-compose)
    return 0
  fi

  DOCKER_COMPOSE_CMD=()
  return 1
}

ensure_docker() {
  if command -v docker >/dev/null 2>&1; then
    log_info "docker already present"
    return 0
  fi

  log_warn "Docker not found"
  if (( AUTO_INSTALL_DEPS )); then
    local package_candidates=()
    if detect_package_manager; then
      case "$PACKAGE_MANAGER" in
        apt)
          package_candidates=(docker.io)
          ;;
        dnf|yum)
          package_candidates=(docker)
          ;;
        zypper)
          package_candidates=(docker)
          ;;
        pacman)
          package_candidates=(docker)
          ;;
        *)
          package_candidates=()
          ;;
      esac
    fi

    local installed=0
    for pkg in "${package_candidates[@]}"; do
      if install_packages "$pkg"; then
        installed=1
        break
      fi
    done

    if (( ! installed )); then
      log_warn "Falling back to Docker convenience script"
      if (( DRY_RUN )); then
        log_info "[dry-run] Would download and execute get.docker.com script"
        installed=1
      else
        if command -v curl >/dev/null 2>&1; then
          curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
          sh /tmp/get-docker.sh
          rm -f /tmp/get-docker.sh
          installed=1
        else
          log_error "curl is required to download the Docker convenience script"
        fi
      fi
    fi

    if (( installed )); then
      if command -v docker >/dev/null 2>&1; then
        log_info "Docker installation completed"
        return 0
      fi
    fi

    log_error "Unable to install Docker automatically"
    return 1
  else
    MISSING_DEPENDENCIES+=("docker")
    return 1
  fi
}

ensure_docker_compose() {
  if set_docker_compose_cmd; then
    log_info "Using Docker Compose command: ${DOCKER_COMPOSE_CMD[*]}"
    return 0
  fi

  log_warn "Docker Compose not available"
  if (( AUTO_INSTALL_DEPS )); then
    local packages_to_try=()
    if detect_package_manager; then
      case "$PACKAGE_MANAGER" in
        apt)
          packages_to_try=(docker-compose-plugin docker-compose)
          ;;
        dnf|yum)
          packages_to_try=(docker-compose-plugin docker-compose)
          ;;
        zypper)
          packages_to_try=(docker-compose)
          ;;
        pacman)
          packages_to_try=(docker-compose)
          ;;
        *)
          packages_to_try=()
          ;;
      esac
    fi

    local success=0
    for pkg in "${packages_to_try[@]}"; do
      if install_packages "$pkg"; then
        success=1
        break
      else
        log_warn "Failed to install $pkg"
      fi
    done

    if (( success )); then
      if set_docker_compose_cmd; then
        log_info "Docker Compose installation completed"
        return 0
      fi
    fi

    log_error "Unable to install Docker Compose automatically"
    return 1
  else
    MISSING_DEPENDENCIES+=("docker compose")
    return 1
  fi
}

start_service_if_possible() {
  local service_name="$1"

  if (( DRY_RUN )); then
    log_info "[dry-run] Would ensure service $service_name is running"
    return 0
  fi

  if command -v systemctl >/dev/null 2>&1; then
    if systemctl is-active --quiet "$service_name"; then
      return 0
    fi
    if systemctl start "$service_name"; then
      log_info "Started service $service_name using systemctl"
      return 0
    else
      log_warn "Failed to start $service_name with systemctl"
    fi
  fi

  if command -v service >/dev/null 2>&1; then
    if service "$service_name" status >/dev/null 2>&1; then
      return 0
    fi
    if service "$service_name" start >/dev/null 2>&1; then
      log_info "Started service $service_name using service command"
      return 0
    else
      log_warn "Failed to start $service_name using service command"
    fi
  fi

  log_warn "Could not manage service $service_name automatically"
  return 1
}

ensure_docker_running() {
  if (( DRY_RUN )); then
    log_info "[dry-run] Would verify Docker daemon status"
    return 0
  fi

  if docker info >/dev/null 2>&1; then
    return 0
  fi

  log_warn "Docker daemon not running; attempting to start"
  start_service_if_possible docker

  if docker info >/dev/null 2>&1; then
    log_info "Docker daemon is running"
    return 0
  fi

  log_error "Docker daemon is not running. Please start it manually and rerun the installer"
  exit 1
}

ensure_dependencies() {
  MISSING_DEPENDENCIES=()

  ensure_command curl
  ensure_command git
  ensure_docker
  ensure_docker_compose

  if (( ${#MISSING_DEPENDENCIES[@]} > 0 )); then
    log_error "Missing dependencies: ${MISSING_DEPENDENCIES[*]}"
    log_error "Install them manually or rerun with --auto-install-deps"
    exit 1
  fi

  if (( DRY_RUN )); then
    return 0
  fi

  ensure_docker_running
  if ! set_docker_compose_cmd; then
    log_error "Docker Compose command is still unavailable after installation"
    exit 1
  fi
}

bring_up_stack() {
  if (( SKIP_START )); then
    log_info "Skipping Docker Compose startup as requested"
    return 0
  fi

  if (( DRY_RUN )); then
    log_info "[dry-run] Would pull container images"
    log_info "[dry-run] Would start the OpsiSuit stack"
    return 0
  fi

  if [[ ! -f "$COMPOSE_FILE" ]]; then
    log_error "Compose file $COMPOSE_FILE not found"
    exit 1
  fi

  if (( ${#DOCKER_COMPOSE_CMD[@]} == 0 )); then
    if ! set_docker_compose_cmd; then
      log_error "Docker Compose command is unavailable"
      exit 1
    fi
  fi

  log_info "Pulling container images"
  pushd "$DOCKER_DIR" >/dev/null
  "${DOCKER_COMPOSE_CMD[@]}" pull
  log_info "Starting OpsiSuit services"
  "${DOCKER_COMPOSE_CMD[@]}" up -d --remove-orphans
  popd >/dev/null
}

main() {
  parse_args "$@"

  ensure_directories
  ensure_env_file
  ensure_config_templates
  ensure_dependencies
  bring_up_stack

  log_info "OpsiSuit installer finished"
}

main "$@"
