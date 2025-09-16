#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCKER_DIR="${PROJECT_ROOT}/docker"
CONFIG_DIR="${PROJECT_ROOT}/configs"
DATA_DIR="${PROJECT_ROOT}/data"
LOG_DIR="${PROJECT_ROOT}/logs"
BACKUP_DIR="${PROJECT_ROOT}/backups"
TMP_DIR="${PROJECT_ROOT}/tmp"

ENV_FILE="${DOCKER_DIR}/.env"
ENV_LOCAL_FILE="${DOCKER_DIR}/.env.local"
COMPOSE_FILE="${DOCKER_DIR}/docker-compose.yml"

DOCKER_CONTAINERS=(
  opsisuit-server
  opsisuit-db
  opsisuit-redis
  opsisuit-pxe
)

RUNTIME_PATHS=(
  "$DATA_DIR"
  "$LOG_DIR"
  "$BACKUP_DIR"
  "$TMP_DIR"
)

DRY_RUN=0
FORCE=0

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
Usage: scripts/opsisuit-rollback.sh [OPTIONS]

Stops all OpsiSuit containers, removes generated configuration/data, and resets the repository to the example state.
Stoppt alle OpsiSuit-Container, entfernt generierte Konfigurationen/Daten und setzt das Repository auf den Beispielzustand zurück.

Options / Optionen:
  -y, --yes, --force   Skip the confirmation prompt / Bestätigung überspringen
      --dry-run        Show the planned actions without executing them / Aktionen nur anzeigen
  -h, --help           Display this help text / Diese Hilfe anzeigen

Examples / Beispiele:
  ./scripts/opsisuit-rollback.sh
  ./scripts/opsisuit-rollback.sh --dry-run
  ./scripts/opsisuit-rollback.sh --yes
USAGE
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -y|--yes|--force)
        FORCE=1
        shift
        ;;
      --dry-run)
        DRY_RUN=1
        shift
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
  done
}

print_plan() {
  log_info "Rollback plan / Ablauf:"
  log_info "  - Stop and remove OpsiSuit Docker stack (containers, volumes, networks)."
  log_info "  - Delete runtime directories: data/, logs/, backups/, tmp/."
  log_info "  - Remove generated configuration files under configs/ (keep *.example)."
  log_info "  - Delete docker/.env and docker/.env.local if present."
}

confirm_action() {
  if (( FORCE )); then
    return
  fi

  printf '%s\n' "This will delete all generated OpsiSuit data, configuration, and Docker containers."
  printf '%s\n' "Dies löscht alle generierten OpsiSuit-Daten, Konfigurationen und Docker-Container."
  read -r -p "Continue? Fortfahren? [y/N]: " answer
  case "${answer:-}" in
    y|Y|yes|YES|j|J|ja|Ja)
      ;;
    *)
      log_info "Rollback aborted."
      exit 0
      ;;
  esac
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

run_compose_down() {
  if [[ ! -f "$COMPOSE_FILE" ]]; then
    log_warn "Compose file not found at $COMPOSE_FILE; skipping docker compose down."
    return 1
  fi

  if ! set_docker_compose_cmd; then
    log_warn "Docker Compose command not available; skipping docker compose down."
    return 1
  fi

  if (( DRY_RUN )); then
    log_info "[dry-run] Would run: (cd docker && ${DOCKER_COMPOSE_CMD[*]} -f docker-compose.yml down --volumes --remove-orphans)"
    return 0
  fi

  if (cd "$DOCKER_DIR" && "${DOCKER_COMPOSE_CMD[@]}" -f "$COMPOSE_FILE" down --volumes --remove-orphans); then
    log_info "Docker stack stopped and removed via compose."
    return 0
  else
    log_warn "docker compose down reported an error."
    return 1
  fi
}

remove_containers_directly() {
  if ! command -v docker >/dev/null 2>&1; then
    log_warn "Docker CLI not available; skipping manual container cleanup."
    return
  fi

  local container
  for container in "${DOCKER_CONTAINERS[@]}"; do
    mapfile -t container_ids < <(docker ps -aq --filter "name=^${container}$")
    if (( ${#container_ids[@]} == 0 )); then
      continue
    fi

    if (( DRY_RUN )); then
      log_info "[dry-run] Would remove container ${container}."
      continue
    fi

    if docker rm -f "${container_ids[@]}" >/dev/null 2>&1; then
      log_info "Removed container ${container}."
    else
      log_warn "Failed to remove container ${container}."
    fi
  done
}

remove_networks_matching() {
  if ! command -v docker >/dev/null 2>&1; then
    return
  fi

  mapfile -t networks < <(docker network ls --format '{{.Name}}' | grep -E 'opsisuit' || true)
  if (( ${#networks[@]} == 0 )); then
    return
  fi

  local network
  for network in "${networks[@]}"; do
    if (( DRY_RUN )); then
      log_info "[dry-run] Would remove network ${network}."
      continue
    fi

    if docker network rm "$network" >/dev/null 2>&1; then
      log_info "Removed network ${network}."
    else
      log_warn "Failed to remove network ${network}."
    fi
  done
}

remove_volumes_matching() {
  if ! command -v docker >/dev/null 2>&1; then
    return
  fi

  mapfile -t volumes < <(docker volume ls --format '{{.Name}}' | grep -E 'opsisuit' || true)
  if (( ${#volumes[@]} == 0 )); then
    return
  fi

  local volume
  for volume in "${volumes[@]}"; do
    if (( DRY_RUN )); then
      log_info "[dry-run] Would remove volume ${volume}."
      continue
    fi

    if docker volume rm "$volume" >/dev/null 2>&1; then
      log_info "Removed volume ${volume}."
    else
      log_warn "Failed to remove volume ${volume}."
    fi
  done
}

safe_remove_path() {
  local target="$1"
  if [[ ! -e "$target" ]]; then
    return 0
  fi

  case "$target" in
    "$PROJECT_ROOT"/*)
      ;;
    *)
      log_error "Refusing to remove path outside project root: $target"
      return 1
      ;;
  esac

  if (( DRY_RUN )); then
    log_info "[dry-run] Would remove ${target#$PROJECT_ROOT/}."
    return 0
  fi

  rm -rf -- "$target"
  log_info "Removed ${target#$PROJECT_ROOT/}."
  return 0
}

cleanup_runtime_directories() {
  local path
  for path in "${RUNTIME_PATHS[@]}"; do
    safe_remove_path "$path"
  done
}

remove_env_files() {
  local file
  for file in "$ENV_FILE" "$ENV_LOCAL_FILE"; do
    if [[ ! -f "$file" ]]; then
      continue
    fi

    if (( DRY_RUN )); then
      log_info "[dry-run] Would remove ${file#$PROJECT_ROOT/}."
    else
      rm -f -- "$file"
      log_info "Removed ${file#$PROJECT_ROOT/}."
    fi
  done
}

reset_generated_configs() {
  if [[ ! -d "$CONFIG_DIR" ]]; then
    return
  fi

  local -a files=()
  while IFS= read -r -d '' file; do
    files+=("$file")
  done < <(find "$CONFIG_DIR" -type f ! -name '*.example' -print0)

  if (( ${#files[@]} == 0 )); then
    log_info "No generated configuration files found under configs/."
    return
  fi

  local file
  for file in "${files[@]}"; do
    if (( DRY_RUN )); then
      log_info "[dry-run] Would remove ${file#$PROJECT_ROOT/}."
    else
      rm -f -- "$file"
      log_info "Removed ${file#$PROJECT_ROOT/}."
    fi
  done
}

teardown_docker_stack() {
  local compose_result=1
  compose_result=1
  if run_compose_down; then
    compose_result=0
  fi

  remove_containers_directly
  remove_networks_matching
  remove_volumes_matching

  if (( compose_result != 0 )); then
    log_warn "Docker stack cleanup relied on manual fallbacks; verify no OpsiSuit containers remain."
  fi
}

main() {
  parse_args "$@"
  print_plan
  confirm_action
  teardown_docker_stack
  cleanup_runtime_directories
  reset_generated_configs
  remove_env_files
  log_info "Rollback complete. Repository is back to the example baseline."
}

main "$@"
