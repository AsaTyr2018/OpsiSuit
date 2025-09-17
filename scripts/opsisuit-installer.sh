#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCKER_DIR="${PROJECT_ROOT}/docker"
CONFIG_DIR="${PROJECT_ROOT}/configs"
DATA_DIR="${PROJECT_ROOT}/data"
LOG_DIR="${PROJECT_ROOT}/logs"
BACKUP_DIR="${PROJECT_ROOT}/backups"

ENV_FILE="${DOCKER_DIR}/.env"
COMPOSE_FILE="${DOCKER_DIR}/docker-compose.yml"

AUTO_INSTALL_DEPS=0
DRY_RUN=0
SKIP_START=0
FORCE_ENV=0
FORCE_CONFIG=0

PACKAGE_MANAGER=""
APT_UPDATED=0

LANGUAGE=""
declare -A EXISTING_ENV_VALUES=()
declare -A ENV_VALUES=()
GENERATED_AGENT_SECRET=""
LEGACY_OPSICONFD_ARGS_VALUE=""
SANITIZED_OPSICONFD_ARGS_VALUE=""

ENV_VARIABLES=(
  DB_ROOT_PASSWORD
  DB_NAME
  DB_USER
  DB_PASSWORD
  DB_PORT
  REDIS_IMAGE
  REDIS_PORT
  REDIS_SERVICE_PORT
  OPSI_ADMIN_USER
  OPSI_ADMIN_PASSWORD
  OPSI_SERVER_FQDN
  OPSI_API_PORT
  OPSI_DEPOT_PORT
  OPSI_WEBUI_PORT
  OPSICONFD_ARGS
  OPSI_SERVER_IMAGE
  AGENT_SECRET
  AGENT_POLL_INTERVAL
  PXE_HTTP_PORT
  PXE_WEBAPP_PORT
  PXE_TFTP_PORT
  SERVICE_UID
  SERVICE_GID
  TIMEZONE
  PXE_IMAGE
)

MISSION_CRITICAL_VARS=(
  DB_ROOT_PASSWORD
  DB_USER
  DB_PASSWORD
  DB_PORT
  REDIS_IMAGE
  REDIS_PORT
  REDIS_SERVICE_PORT
  OPSI_API_PORT
  OPSI_DEPOT_PORT
  OPSI_SERVER_IMAGE
  OPSICONFD_ARGS
  AGENT_SECRET
  PXE_HTTP_PORT
  PXE_WEBAPP_PORT
  PXE_TFTP_PORT
  SERVICE_UID
  SERVICE_GID
  PXE_IMAGE
)

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

language_is_de() {
  [[ "$LANGUAGE" == "DE" ]]
}

select_language() {
  local prompt="Sprache auswählen / Select language [DE/en]: "
  local answer=""

  while true; do
    read -r -p "$prompt" answer
    answer=${answer:-DE}
    case "${answer^^}" in
      DE)
        LANGUAGE="DE"
        log_info "Sprache: Deutsch"
        break
        ;;
      EN)
        LANGUAGE="EN"
        log_info "Language: English"
        break
        ;;
      *)
        printf 'Bitte "DE" oder "EN" eingeben / Please type "DE" or "EN".\n'
        ;;
    esac
  done
}

load_existing_env_values() {
  EXISTING_ENV_VALUES=()

  if (( FORCE_ENV )); then
    return
  fi

  if [[ ! -f "$ENV_FILE" ]]; then
    return
  fi

  while IFS='=' read -r key value; do
    if [[ -z "$key" || "$key" == '#'* ]]; then
      continue
    fi

    if [[ "$key" == "OPSICONFD_ARGS" ]]; then
      local normalized
      normalized="$(sanitize_opsiconfd_args_value "$value")"
      if [[ "$normalized" != "$value" ]]; then
        LEGACY_OPSICONFD_ARGS_VALUE="$value"
        value="$normalized"
      fi
      SANITIZED_OPSICONFD_ARGS_VALUE="$value"
    fi
    EXISTING_ENV_VALUES["$key"]="$value"
  done <"$ENV_FILE"

  if [[ -n "$LEGACY_OPSICONFD_ARGS_VALUE" ]]; then
    if language_is_de; then
      log_warn "OPSICONFD_ARGS enthielt das veraltete '--ssl'-Flag und wurde auf '${SANITIZED_OPSICONFD_ARGS_VALUE}' normalisiert."
    else
      log_warn "Detected deprecated '--ssl' flag in OPSICONFD_ARGS; normalizing to '${SANITIZED_OPSICONFD_ARGS_VALUE}'."
    fi
  fi
}

sanitize_opsiconfd_args_value() {
  local raw_value="$1"
  local stripped_value="${raw_value%$'\r'}"
  local quote_char=""

  if (( ${#stripped_value} >= 2 )); then
    local first_char="${stripped_value:0:1}"
    local last_char="${stripped_value: -1}"
    if [[ "$first_char" == "\"" && "$last_char" == "\"" ]]; then
      quote_char='"'
      stripped_value="${stripped_value:1:${#stripped_value}-2}"
    elif [[ "$first_char" == "'" && "$last_char" == "'" ]]; then
      quote_char="'"
      stripped_value="${stripped_value:1:${#stripped_value}-2}"
    fi
  fi

  read -ra tokens <<<"$stripped_value"

  declare -a cleaned_tokens=()
  local has_config_file=0

  for ((i = 0; i < ${#tokens[@]}; i++)); do
    local token="${tokens[i]}"

    case "$token" in
      --ssl)
        if (( i + 1 < ${#tokens[@]} )); then
          local next_token="${tokens[i + 1]}"
          if [[ "$next_token" != --* ]]; then
            ((i++))
          fi
        fi
        continue
        ;;
      --ssl=*|--no-ssl|--disable-ssl|--enable-ssl)
        continue
        ;;
    esac

    case "$token" in
      --config-file)
        has_config_file=1
        cleaned_tokens+=("$token")
        if (( i + 1 < ${#tokens[@]} )); then
          ((i++))
          cleaned_tokens+=("${tokens[i]}")
        fi
        ;;
      --config-file=*)
        has_config_file=1
        cleaned_tokens+=("$token")
        ;;
      "")
        ;;
      *)
        cleaned_tokens+=("$token")
        ;;
    esac
  done

  local sanitized=""
  for token in "${cleaned_tokens[@]}"; do
    [[ -z "$token" ]] && continue
    if [[ -n "$sanitized" ]]; then
      sanitized+=" "
    fi
    sanitized+="$token"
  done

  if (( ! has_config_file )); then
    if [[ -n "$sanitized" ]]; then
      sanitized+=" "
    fi
    sanitized+="--config-file=/etc/opsi/opsiconfd.conf"
  fi

  if [[ -n "$quote_char" ]]; then
    printf '%s%s%s' "$quote_char" "$sanitized" "$quote_char"
  else
    printf '%s' "$sanitized"
  fi
}

maybe_patch_legacy_opsiconfd_args() {
  if [[ -z "$LEGACY_OPSICONFD_ARGS_VALUE" ]]; then
    return
  fi

  local new_value="$SANITIZED_OPSICONFD_ARGS_VALUE"
  if [[ -z "$new_value" ]]; then
    new_value="--config-file=/etc/opsi/opsiconfd.conf"
  fi

  if (( DRY_RUN )); then
    if language_is_de; then
      log_info "[dry-run] Würde OPSICONFD_ARGS in ${ENV_FILE} von '${LEGACY_OPSICONFD_ARGS_VALUE}' auf '${new_value}' aktualisieren."
    else
      log_info "[dry-run] Would update OPSICONFD_ARGS in ${ENV_FILE} from '${LEGACY_OPSICONFD_ARGS_VALUE}' to '${new_value}'."
    fi
    return
  fi

  if [[ ! -f "$ENV_FILE" ]]; then
    return
  fi

  local tmp_file
  tmp_file="$(mktemp "${ENV_FILE}.XXXX")"
  local replaced=0

  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ $line =~ ^([[:space:]]*OPSICONFD_ARGS[[:space:]]*=[[:space:]]*)(.*)$ ]]; then
      printf '%s%s\n' "${BASH_REMATCH[1]}" "$new_value" >>"$tmp_file"
      replaced=1
    else
      printf '%s\n' "$line" >>"$tmp_file"
    fi
  done <"$ENV_FILE"

  if (( replaced )); then
    local backup="${ENV_FILE}.bak.sslfix.$(date +%Y%m%d%H%M%S)"
    cp "$ENV_FILE" "$backup"
    mv "$tmp_file" "$ENV_FILE"
    if language_is_de; then
      log_info "OPSICONFD_ARGS in ${ENV_FILE} wurde aktualisiert (Sicherung: $backup)."
    else
      log_info "Updated OPSICONFD_ARGS in ${ENV_FILE} (backup: $backup)."
    fi
  else
    rm -f "$tmp_file"
  fi
}

get_env_default() {
  case "$1" in
    DB_ROOT_PASSWORD) echo "" ;;
    DB_NAME) echo "opsi" ;;
    DB_USER) echo "opsi" ;;
    DB_PASSWORD) echo "" ;;
    DB_PORT) echo "3306" ;;
    REDIS_IMAGE) echo "redis/redis-stack-server:latest" ;;
    REDIS_PORT) echo "6379" ;;
    REDIS_SERVICE_PORT) echo "6379" ;;
    OPSI_ADMIN_USER) echo "opsiadmin" ;;
    OPSI_ADMIN_PASSWORD) echo "" ;;
    OPSI_SERVER_FQDN) echo "opsi.local" ;;
    OPSI_API_PORT) echo "4447" ;;
    OPSI_DEPOT_PORT) echo "4441" ;;
    OPSI_WEBUI_PORT) echo "4443" ;;
    OPSICONFD_ARGS) echo "--config-file=/etc/opsi/opsiconfd.conf" ;;
    OPSI_SERVER_IMAGE) echo "uibmz/opsi-server:4.2" ;;
    AGENT_SECRET) echo "ChangeMeAgentSecret!" ;;
    AGENT_POLL_INTERVAL) echo "3600" ;;
    PXE_HTTP_PORT) echo "8080" ;;
    PXE_WEBAPP_PORT) echo "3000" ;;
    PXE_TFTP_PORT) echo "69" ;;
    SERVICE_UID) echo "1000" ;;
    SERVICE_GID) echo "1000" ;;
    TIMEZONE) echo "UTC" ;;
    PXE_IMAGE) echo "netbootxyz/netbootxyz:latest" ;;
    *) echo "" ;;
  esac
}

get_effective_env_value() {
  local var="$1"

  if [[ -n "${ENV_VALUES[$var]:-}" ]]; then
    echo "${ENV_VALUES[$var]}"
    return
  fi

  if [[ -n "${EXISTING_ENV_VALUES[$var]:-}" ]]; then
    echo "${EXISTING_ENV_VALUES[$var]}"
    return
  fi

  get_env_default "$var"
}

is_env_required() {
  case "$1" in
    DB_ROOT_PASSWORD|DB_PASSWORD|OPSI_ADMIN_PASSWORD)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

is_mission_critical_var() {
  case "$1" in
    DB_ROOT_PASSWORD|DB_USER|DB_PASSWORD|DB_PORT|\
    REDIS_IMAGE|REDIS_PORT|REDIS_SERVICE_PORT|\
    OPSI_API_PORT|OPSI_DEPOT_PORT|OPSI_SERVER_IMAGE|OPSICONFD_ARGS|\
    AGENT_SECRET|PXE_HTTP_PORT|PXE_WEBAPP_PORT|\
    PXE_TFTP_PORT|SERVICE_UID|SERVICE_GID|PXE_IMAGE)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

is_env_secret() {
  case "$1" in
    DB_ROOT_PASSWORD|DB_PASSWORD|OPSI_ADMIN_PASSWORD|AGENT_SECRET)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

warn_required_input() {
  if language_is_de; then
    log_warn "Dieser Wert ist erforderlich."
  else
    log_warn "This value is required."
  fi
}

warn_invalid_port() {
  if language_is_de; then
    log_warn "Bitte eine gültige Portnummer zwischen 1 und 65535 eingeben."
  else
    log_warn "Please provide a valid port number between 1 and 65535."
  fi
}

warn_invalid_integer() {
  if language_is_de; then
    log_warn "Bitte eine gültige Ganzzahl größer oder gleich 0 eingeben."
  else
    log_warn "Please provide a valid integer greater than or equal to 0."
  fi
}

warn_invalid_fqdn() {
  if language_is_de; then
    log_warn "Bitte einen vollqualifizierten Domainnamen angeben (z. B. opsi.example.local)."
  else
    log_warn "Please provide a fully qualified domain name (e.g. opsi.example.local)."
  fi
}

generate_random_string() {
  local length=${1:-32}
  local value=""

  if command -v python3 >/dev/null 2>&1; then
    value="$(python3 - "$length" <<'PY'
import secrets, string, sys
length = int(sys.argv[1])
alphabet = string.ascii_letters + string.digits
print(''.join(secrets.choice(alphabet) for _ in range(length)))
PY
)"
  elif command -v python >/dev/null 2>&1; then
    value="$(python - "$length" <<'PY'
import secrets, string, sys
length = int(sys.argv[1])
alphabet = string.ascii_letters + string.digits
print(''.join(secrets.choice(alphabet) for _ in range(length)))
PY
)"
  else
    value="$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c "$length")"
  fi

  if [[ -z "$value" || ${#value} -lt $length ]]; then
    log_error "Failed to generate random string of length $length"
    exit 1
  fi

  printf '%s' "$value"
}

generate_db_username() {
  local random_part
  random_part="$(generate_random_string 10)"
  printf 'opsi_%s' "$random_part"
}

generate_secure_password() {
  local length=${1:-32}
  generate_random_string "$length"
}

generate_agent_secret() {
  generate_secure_password 48
}

generate_mission_critical_value() {
  local var="$1"

  case "$var" in
    DB_ROOT_PASSWORD)
      generate_secure_password 32
      ;;
    DB_PASSWORD)
      generate_secure_password 32
      ;;
    DB_USER)
      generate_db_username
      ;;
    AGENT_SECRET)
      local secret
      secret="$(generate_agent_secret)"
      GENERATED_AGENT_SECRET="$secret"
      printf '%s' "$secret"
      ;;
    *)
      printf '%s' "$(get_env_default "$var")"
      ;;
  esac
}

build_prompt() {
  local var="$1"
  local default_value="$2"
  local label=""

  if language_is_de; then
    case "$var" in
      DB_ROOT_PASSWORD) label="Datenbank-Root-Passwort" ;;
      DB_NAME) label="Name der OPSI-Datenbank" ;;
      DB_USER) label="Datenbankbenutzer" ;;
      DB_PASSWORD) label="Passwort für den Datenbankbenutzer" ;;
      DB_PORT) label="Datenbank-Portnummer" ;;
      REDIS_IMAGE) label="Container-Image für Redis" ;;
      REDIS_PORT) label="Externer Redis-Port (Host)" ;;
      REDIS_SERVICE_PORT) label="Interner Redis-Port (Container)" ;;
      OPSI_ADMIN_USER) label="OPSI-Administratorbenutzer" ;;
      OPSI_ADMIN_PASSWORD) label="Passwort für den OPSI-Administrator" ;;
      OPSI_SERVER_FQDN) label="FQDN des OPSI-Servers" ;;
      OPSI_API_PORT) label="Port für die OPSI Config API" ;;
      OPSI_DEPOT_PORT) label="OPSI-Depot-Port" ;;
      OPSI_WEBUI_PORT) label="Port für die OPSI Weboberfläche" ;;
      OPSI_SERVER_IMAGE) label="Container-Image für den OPSI-Server" ;;
      AGENT_SECRET) label="Agent-Secret für Client-Registrierung (Änderung empfohlen)" ;;
      AGENT_POLL_INTERVAL) label="Abfrageintervall des Agenten in Sekunden" ;;
      PXE_HTTP_PORT) label="HTTP-Port für PXE-Bereitstellung" ;;
      PXE_WEBAPP_PORT) label="Webinterface-Port für netboot.xyz" ;;
      PXE_TFTP_PORT) label="UDP-Port für PXE/TFTP" ;;
      SERVICE_UID) label="UID für Container-Dienste" ;;
      SERVICE_GID) label="GID für Container-Dienste" ;;
      TIMEZONE) label="Zeitzone (z. B. Europe/Berlin)" ;;
      PXE_IMAGE) label="Container-Image für den PXE-Dienst" ;;
      *) label="$var" ;;
    esac

    if is_env_required "$var"; then
      label+=" (Pflichtfeld)"
    fi

    if [[ -n "$default_value" ]]; then
      label+=" [Standard: $default_value]"
    fi

    printf '%s: ' "$label"
  else
    case "$var" in
      DB_ROOT_PASSWORD) label="Database root password" ;;
      DB_NAME) label="OPSI database name" ;;
      DB_USER) label="Database user" ;;
      DB_PASSWORD) label="Password for the database user" ;;
      DB_PORT) label="Database port number" ;;
      REDIS_IMAGE) label="Container image for Redis" ;;
      REDIS_PORT) label="Redis host port" ;;
      REDIS_SERVICE_PORT) label="Redis service port (inside container network)" ;;
      OPSI_ADMIN_USER) label="OPSI administrator user" ;;
      OPSI_ADMIN_PASSWORD) label="Password for the OPSI administrator" ;;
      OPSI_SERVER_FQDN) label="Fully qualified domain name of the OPSI server" ;;
      OPSI_API_PORT) label="Port for the OPSI Config API" ;;
      OPSI_DEPOT_PORT) label="OPSI depot port" ;;
      OPSI_WEBUI_PORT) label="Port for the OPSI web interface" ;;
      OPSI_SERVER_IMAGE) label="Container image for the OPSI server" ;;
      AGENT_SECRET) label="Agent secret for client registration (change recommended)" ;;
      AGENT_POLL_INTERVAL) label="Agent polling interval in seconds" ;;
      PXE_HTTP_PORT) label="HTTP port for PXE provisioning" ;;
      PXE_WEBAPP_PORT) label="Web interface port for netboot.xyz" ;;
      PXE_TFTP_PORT) label="UDP port for PXE/TFTP" ;;
      SERVICE_UID) label="UID for container services" ;;
      SERVICE_GID) label="GID for container services" ;;
      TIMEZONE) label="Timezone (e.g. Europe/Berlin)" ;;
      PXE_IMAGE) label="Container image for the PXE service" ;;
      *) label="$var" ;;
    esac

    if is_env_required "$var"; then
      label+=" (required)"
    fi

    if [[ -n "$default_value" ]]; then
      label+=" [default: $default_value]"
    fi

    printf '%s: ' "$label"
  fi
}

validate_env_value() {
  local var="$1"
  local value="$2"
  local numeric_value=0

  case "$var" in
    DB_PORT|REDIS_PORT|REDIS_SERVICE_PORT|OPSI_API_PORT|OPSI_DEPOT_PORT|OPSI_WEBUI_PORT|PXE_HTTP_PORT|PXE_WEBAPP_PORT|PXE_TFTP_PORT)
      if [[ ! "$value" =~ ^[0-9]+$ ]]; then
        warn_invalid_port
        return 1
      fi
      numeric_value=$((10#$value))
      if (( numeric_value < 1 || numeric_value > 65535 )); then
        warn_invalid_port
        return 1
      fi
      ;;
    SERVICE_UID|SERVICE_GID|AGENT_POLL_INTERVAL)
      if [[ ! "$value" =~ ^[0-9]+$ ]]; then
        warn_invalid_integer
        return 1
      fi
      ;;
    OPSI_SERVER_FQDN)
      if [[ ! "$value" =~ ^[A-Za-z0-9]([-A-Za-z0-9]*[A-Za-z0-9])?(\.[A-Za-z0-9]([-A-Za-z0-9]*[A-Za-z0-9])?)+$ ]]; then
        warn_invalid_fqdn
        return 1
      fi
      ;;
  esac

  return 0
}

prompt_env_var() {
  local var="$1"
  local default_value="$2"
  local value=""

  while true; do
    build_prompt "$var" "$default_value"
    if is_env_secret "$var"; then
      read -r -s value
      printf '\n'
    else
      read -r value
    fi

    if [[ -z "$value" ]]; then
      value="$default_value"
    fi

    if [[ -z "$value" ]] && is_env_required "$var"; then
      warn_required_input
      continue
    fi

    if [[ -n "$value" ]] && ! validate_env_value "$var" "$value"; then
      continue
    fi

    ENV_VALUES["$var"]="$value"
    break
  done
}

display_env_summary() {
  if language_is_de; then
    log_info "Zusammenfassung der gewählten Einstellungen:"
  else
    log_info "Summary of selected settings:"
  fi

  local hidden_label="(hidden)"
  if language_is_de; then
    hidden_label="(versteckt)"
  fi

  for var in "${ENV_VARIABLES[@]}"; do
    local value="${ENV_VALUES[$var]-}"
    if is_env_secret "$var" && [[ -n "$value" ]]; then
      printf '  %s=%s\n' "$var" "$hidden_label"
    else
      local suffix=""
      if is_mission_critical_var "$var"; then
        if language_is_de; then
          suffix=" (missionskritisch)"
        else
          suffix=" (mission critical)"
        fi
      fi
      printf '  %s=%s%s\n' "$var" "$value" "$suffix"
    fi
  done
}

prompt_yes_no() {
  local question="$1"
  local default_answer="$2"
  local prompt=""
  local answer=""

  if language_is_de; then
    if [[ "$default_answer" == "y" ]]; then
      prompt="$question [J/n]: "
    else
      prompt="$question [j/N]: "
    fi
  else
    if [[ "$default_answer" == "y" ]]; then
      prompt="$question [Y/n]: "
    else
      prompt="$question [y/N]: "
    fi
  fi

  while true; do
    read -r -p "$prompt" answer
    if [[ -z "$answer" ]]; then
      answer="$default_answer"
    fi

    case "${answer,,}" in
      y|yes|j|ja)
        return 0
        ;;
      n|no|nein)
        return 1
        ;;
      *)
        if language_is_de; then
          printf 'Bitte mit "j"/"n" antworten.\n'
        else
          printf 'Please answer with "y"/"n".\n'
        fi
        ;;
    esac
  done
}

prompt_reuse_existing_env() {
  local answer=""
  local prompt=""
  local default_choice="reuse"

  while true; do
    if language_is_de; then
      prompt="Reuse oder neu erstellen? [Reuse/neu]: "
    else
      prompt="Reuse or create new? [reuse/new]: "
    fi

    read -r -p "$prompt" answer
    if [[ -z "$answer" ]]; then
      answer="$default_choice"
    fi

    local normalized="${answer,,}"
    case "$normalized" in
      reuse|r|wiederverwenden|wieder|verwenden|w)
        return 0
        ;;
      neu|new|n)
        return 1
        ;;
      *)
        if language_is_de; then
          printf 'Bitte mit "Reuse" oder "neu" antworten.\n'
        else
          printf 'Please answer with "reuse" or "new".\n'
        fi
        ;;
    esac
  done
}

write_env_file() {
  if (( DRY_RUN )); then
    log_info "[dry-run] Would write configuration to ${ENV_FILE}"
    return
  fi

  if [[ -f "$ENV_FILE" ]]; then
    local backup="${ENV_FILE}.bak.$(date +%Y%m%d%H%M%S)"
    cp "$ENV_FILE" "$backup"
    if language_is_de; then
      log_info "Bestehende Datei nach $backup gesichert."
    else
      log_info "Existing file backed up to $backup."
    fi
  fi

  local tmp_file
  tmp_file="$(mktemp "${ENV_FILE}.XXXX")"

  {
    printf '# Generated by opsisuit-installer on %s\n' "$(date -Iseconds)"
    for var in "${ENV_VARIABLES[@]}"; do
      printf '%s=%s\n' "$var" "${ENV_VALUES[$var]-}"
    done
  } >"$tmp_file"

  mv "$tmp_file" "$ENV_FILE"

  if language_is_de; then
    log_info "Konfigurationswerte in ${ENV_FILE} geschrieben."
  else
    log_info "Configuration values written to ${ENV_FILE}."
  fi
}

ensure_env_file() {
  load_existing_env_values

  local env_example="${DOCKER_DIR}/.env.example"
  local reuse_existing_env=0
  local ignore_existing_defaults=0

  if (( FORCE_ENV )); then
    ignore_existing_defaults=1
  fi

  if (( ! FORCE_ENV )) && [[ -f "$ENV_FILE" ]]; then
    local differs_from_example=1
    if [[ -f "$env_example" ]] && cmp -s "$ENV_FILE" "$env_example"; then
      differs_from_example=0
    fi

    if (( differs_from_example )); then
      if language_is_de; then
        log_info "Eine bestehende docker/.env wurde gefunden."
      else
        log_info "An existing docker/.env file was found."
      fi

      if prompt_reuse_existing_env; then
        reuse_existing_env=1
      else
        ignore_existing_defaults=1
        if language_is_de; then
          log_info "docker/.env wird neu erstellt."
        else
          log_info "docker/.env will be recreated."
        fi
      fi
    fi
  fi

  if (( reuse_existing_env )); then
    maybe_patch_legacy_opsiconfd_args
    if language_is_de; then
      log_info "Bestehende docker/.env wird verwendet."
    else
      log_info "Reusing existing docker/.env."
    fi
    return
  fi

  if language_is_de; then
    log_info "Interaktiver Installer gestartet."
    log_info "Drücken Sie Enter, um vorgeschlagene Standardwerte zu übernehmen."
    if (( FORCE_ENV )); then
      log_info "Vorhandene Werte werden aufgrund von --force-env ignoriert."
    elif (( ignore_existing_defaults )); then
      log_info "Vorhandene Werte werden verworfen und durch neue Eingaben ersetzt."
    elif [[ -f "$ENV_FILE" ]]; then
      log_info "Vorhandene Werte werden als Vorschläge angezeigt."
    fi
  else
    log_info "Interactive installer started."
    log_info "Press Enter to accept the suggested defaults."
    if (( FORCE_ENV )); then
      log_info "Existing values are ignored because --force-env is set."
    elif (( ignore_existing_defaults )); then
      log_info "Existing values will be discarded and replaced with new input."
    elif [[ -f "$ENV_FILE" ]]; then
      log_info "Existing values are presented as suggestions."
    fi
  fi

  ENV_VALUES=()

  if (( ${#MISSION_CRITICAL_VARS[@]} )); then
    if language_is_de; then
      log_info "Folgende missionskritische Variablen werden automatisch verwaltet und nicht abgefragt:"
    else
      log_info "The following mission critical variables are managed automatically and are not prompted:"
    fi

    for critical_var in "${MISSION_CRITICAL_VARS[@]}"; do
      local managed_value=""
      local reuse_existing_value=0

      if (( ! ignore_existing_defaults )) && [[ -v EXISTING_ENV_VALUES[$critical_var] ]]; then
        managed_value="${EXISTING_ENV_VALUES[$critical_var]}"
        reuse_existing_value=1
      else
        managed_value="$(generate_mission_critical_value "$critical_var")"
      fi

      ENV_VALUES["$critical_var"]="$managed_value"

      local display_value="$managed_value"
      if is_env_secret "$critical_var" && [[ -n "$display_value" ]]; then
        if language_is_de; then
          display_value="(versteckt)"
        else
          display_value="(hidden)"
        fi
      fi

      local note=""
      if (( reuse_existing_value )); then
        if language_is_de; then
          note=" (bestehender Wert)"
        else
          note=" (existing value)"
        fi
      else
        if language_is_de; then
          note=" (automatisch gesetzt)"
        else
          note=" (auto-managed)"
        fi
      fi

      log_info "  ${critical_var}=${display_value}${note}"
    done
  fi

  for var in "${ENV_VARIABLES[@]}"; do
    local default_value=""

    if is_mission_critical_var "$var"; then
      continue
    fi

    if (( ! ignore_existing_defaults )) && [[ -v EXISTING_ENV_VALUES[$var] ]]; then
      default_value="${EXISTING_ENV_VALUES[$var]}"
    else
      default_value="$(get_env_default "$var")"
    fi

    prompt_env_var "$var" "$default_value"
  done

  display_env_summary

  local question=""
  if language_is_de; then
    question="Konfiguration in ${ENV_FILE} schreiben?"
  else
    question="Write configuration to ${ENV_FILE}?"
  fi

  if prompt_yes_no "$question" "y"; then
    write_env_file
  else
    if language_is_de; then
      log_error "Installer abgebrochen, keine Änderungen vorgenommen."
    else
      log_error "Installer aborted, no changes applied."
    fi
    exit 1
  fi
}

usage() {
  cat <<'USAGE'
OpsiSuit Installer
===================

Bootstraps the OpsiSuit Docker stack. The installer checks required
dependencies, prepares configuration files and, unless told otherwise,
starts the Docker Compose stack. The script interactively collects
environment-specific settings in German or English.

Usage: scripts/opsisuit-installer.sh [options]

Options:
  --auto-install-deps    Install missing dependencies with the detected
                         package manager (requires root).
  --dry-run              Print the actions without modifying the system.
  --skip-start           Do not start the Docker Compose stack.
  --force-env            Ignore existing docker/.env values when prompting.
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
    "$DATA_DIR/opsi/etc"
    "$DATA_DIR/opsi/etc/opsi"
    "$DATA_DIR/opsi/etc/opsi/ssl"
    "$DATA_DIR/opsi/lib"
    "$DATA_DIR/opsi/log"
    "$DATA_DIR/opsi/opsiconfd"
    "$DATA_DIR/inventory"
    "$DATA_DIR/pxe"
    "$DATA_DIR/redis"
    "$LOG_DIR"
    "$LOG_DIR/opsi-server"
    "$BACKUP_DIR"
    "$CONFIG_DIR"
    "$CONFIG_DIR/opsi"
    "$CONFIG_DIR/pxe"
    "$CONFIG_DIR/agent"
    "$CONFIG_DIR/inventory"
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

render_opsiconfd_conf() {
  local template="$CONFIG_DIR/opsi/opsiconfd.conf.example"
  local destination="$DATA_DIR/opsi/etc/opsi/opsiconfd.conf"
  local legacy_destination="$DATA_DIR/opsi/etc/opsiconfd.conf"

  if [[ ! -f "$template" ]]; then
    log_warn "Template $template is missing; skipping opsiconfd configuration"
    return
  fi

  if [[ -f "$legacy_destination" && ! -f "$destination" ]]; then
    if (( DRY_RUN )); then
      if language_is_de; then
        log_info "[dry-run] Würde bestehende Datei ${legacy_destination} nach ${destination} verschieben."
      else
        log_info "[dry-run] Would migrate existing ${legacy_destination} to ${destination}."
      fi
    else
      ensure_directory "$(dirname "$destination")"
      mv "$legacy_destination" "$destination"
      if language_is_de; then
        log_info "Bestehende opsiconfd.conf nach ${destination} verschoben."
      else
        log_info "Migrated legacy opsiconfd.conf to ${destination}."
      fi
    fi
  fi

  if [[ -f "$destination" && $FORCE_CONFIG -eq 0 ]]; then
    log_info "Existing $destination detected; leaving untouched"
    return
  fi

  if (( DRY_RUN )); then
    log_info "[dry-run] Would render opsiconfd configuration to $destination"
    return
  fi

  local api_port depot_port ssl_cert_path ssl_key_path ssl_ca_path tmp_file
  api_port="4447"
  depot_port="4441"
  ssl_cert_path="/etc/opsi/ssl/opsiconfd-cert.pem"
  ssl_key_path="/etc/opsi/ssl/opsiconfd-key.pem"
  ssl_ca_path="/etc/opsi/ssl/opsiconfd-ca.pem"

  ensure_directory "$(dirname "$destination")"

  tmp_file="$(mktemp "${destination}.XXXX")"

  while IFS= read -r line; do
    line=${line//@OPSI_API_INTERNAL_PORT@/$api_port}
    line=${line//@OPSI_DEPOT_INTERNAL_PORT@/$depot_port}
    line=${line//@OPSI_SSL_CERT_PATH@/$ssl_cert_path}
    line=${line//@OPSI_SSL_KEY_PATH@/$ssl_key_path}
    line=${line//@OPSI_SSL_CA_PATH@/$ssl_ca_path}
    printf '%s\n' "$line"
  done <"$template" >"$tmp_file"

  mv "$tmp_file" "$destination"
  log_info "Rendered $destination from template"
}

ensure_opsiconfd_ssl_assets() {
  local ssl_dir="$DATA_DIR/opsi/etc/opsi/ssl"
  local key_file="$ssl_dir/opsiconfd-key.pem"
  local cert_file="$ssl_dir/opsiconfd-cert.pem"
  local bundle_file="$ssl_dir/opsiconfd.pem"
  local ca_file="$ssl_dir/opsiconfd-ca.pem"
  local fqdn="$(get_effective_env_value OPSI_SERVER_FQDN)"
  local regenerate=0

  ensure_directory "$ssl_dir"

  if [[ -z "$fqdn" ]]; then
    fqdn="opsi.local"
  fi

  if [[ -f "$key_file" && -f "$cert_file" ]]; then
    if (( FORCE_CONFIG )); then
      regenerate=1
    else
      if language_is_de; then
        log_info "Vorhandene TLS-Schlüssel/Zertifikate für opsiconfd werden weiterverwendet."
      else
        log_info "Existing opsiconfd TLS key/certificate detected; reusing them."
      fi
      return
    fi
  else
    regenerate=1
  fi

  if (( ! regenerate )); then
    return
  fi

  if (( DRY_RUN )); then
    if language_is_de; then
      log_info "[dry-run] Würde selbstsigniertes TLS-Zertifikat für ${fqdn} in ${ssl_dir} erzeugen."
    else
      log_info "[dry-run] Would generate a self-signed TLS certificate for ${fqdn} inside ${ssl_dir}."
    fi
    return
  fi

  local timestamp backup_dir
  if [[ -f "$key_file" || -f "$cert_file" || -f "$bundle_file" || -f "$ca_file" ]]; then
    backup_dir="$BACKUP_DIR/ssl"
    ensure_directory "$backup_dir"
    timestamp="$(date +%Y%m%d%H%M%S)"
    [[ -f "$key_file" ]] && cp "$key_file" "$backup_dir/opsiconfd-key.pem.$timestamp"
    [[ -f "$cert_file" ]] && cp "$cert_file" "$backup_dir/opsiconfd-cert.pem.$timestamp"
    [[ -f "$bundle_file" ]] && cp "$bundle_file" "$backup_dir/opsiconfd.pem.$timestamp"
    [[ -f "$ca_file" ]] && cp "$ca_file" "$backup_dir/opsiconfd-ca.pem.$timestamp"
    if language_is_de; then
      log_info "Bestehende TLS-Dateien nach ${backup_dir} gesichert (Zeitstempel ${timestamp})."
    else
      log_info "Backed up existing TLS assets to ${backup_dir} (timestamp ${timestamp})."
    fi
  fi

  local tmpdir
  tmpdir="$(mktemp -d)"

  local openssl_config="$tmpdir/opsiconfd.cnf"
  local short_name="${fqdn%%.*}"
  local -a dns_sans=("$fqdn")

  if [[ -n "$short_name" && "$short_name" != "$fqdn" ]]; then
    dns_sans+=("$short_name")
  fi
  dns_sans+=("localhost")

  {
    printf '[req]\n'
    printf 'default_bits = 4096\n'
    printf 'prompt = no\n'
    printf 'default_md = sha256\n'
    printf 'req_extensions = req_ext\n'
    printf 'distinguished_name = dn\n'
    printf '\n[dn]\n'
    printf 'CN = %s\n' "$fqdn"
    printf '\n[req_ext]\n'
    printf 'subjectAltName = @alt_names\n'
    printf '\n[alt_names]\n'
    local idx=1
    local san
    for san in "${dns_sans[@]}"; do
      printf 'DNS.%d = %s\n' "$idx" "$san"
      ((idx++))
    done
    printf 'IP.1 = 127.0.0.1\n'
    printf 'IP.2 = ::1\n'
  } >"$openssl_config"

  openssl req -x509 -new -nodes -newkey rsa:4096 \
    -days 825 \
    -keyout "$tmpdir/opsiconfd-key.pem" \
    -out "$tmpdir/opsiconfd-cert.pem" \
    -config "$openssl_config" \
    -extensions req_ext >/dev/null

  install -m 600 "$tmpdir/opsiconfd-key.pem" "$key_file"
  install -m 644 "$tmpdir/opsiconfd-cert.pem" "$cert_file"
  cat "$tmpdir/opsiconfd-key.pem" "$tmpdir/opsiconfd-cert.pem" >"$tmpdir/opsiconfd.pem"
  install -m 600 "$tmpdir/opsiconfd.pem" "$bundle_file"
  install -m 644 "$tmpdir/opsiconfd-cert.pem" "$ca_file"

  rm -rf "$tmpdir"

  if language_is_de; then
    log_info "Selbstsigniertes Zertifikat für ${fqdn} erzeugt."
  else
    log_info "Generated self-signed TLS certificate for ${fqdn}."
  fi
}

ensure_config_templates() {
  copy_template "$CONFIG_DIR/opsi/opsi.conf.example" "$CONFIG_DIR/opsi/opsi.conf" "$FORCE_CONFIG"
  copy_template "$CONFIG_DIR/pxe/pxe.conf.example" "$CONFIG_DIR/pxe/pxe.conf" "$FORCE_CONFIG"
  copy_template "$CONFIG_DIR/agent/client-agent.conf.example" "$CONFIG_DIR/agent/client-agent.conf" "$FORCE_CONFIG"
  copy_template "$CONFIG_DIR/inventory/auto-inventory.yml.example" "$CONFIG_DIR/inventory/auto-inventory.yml" "$FORCE_CONFIG"
  render_opsiconfd_conf
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
  ensure_command openssl
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

is_container_running() {
  local container_name="$1"

  docker inspect -f '{{.State.Running}}' "$container_name" 2>/dev/null | grep -q '^true$'
}

wait_for_container_running() {
  local container_name="$1"
  local timeout_seconds=${2:-60}
  local interval_seconds=2
  local waited=0

  while (( waited < timeout_seconds )); do
    if is_container_running "$container_name"; then
      return 0
    fi
    sleep "$interval_seconds"
    (( waited += interval_seconds ))
  done

  return 1
}

ensure_opsi_admin_account() {
  if (( SKIP_START )); then
    if language_is_de; then
      log_info "Überspringe Erstellung des OPSI-Administrator-Kontos, da --skip-start gesetzt ist."
    else
      log_info "Skipping OPSI administrator account provisioning because --skip-start is set."
    fi
    return 0
  fi

  local admin_user
  local admin_password
  local container_name="opsisuit-server"

  admin_user="$(get_effective_env_value OPSI_ADMIN_USER)"
  admin_password="$(get_effective_env_value OPSI_ADMIN_PASSWORD)"

  if [[ -z "$admin_user" ]]; then
    if language_is_de; then
      log_warn "OPSI_ADMIN_USER ist nicht gesetzt; überspringe die Provisionierung des Administrator-Kontos."
    else
      log_warn "OPSI_ADMIN_USER is not set; skipping administrator account provisioning."
    fi
    return 0
  fi

  if [[ -z "$admin_password" ]]; then
    if language_is_de; then
      log_warn "OPSI_ADMIN_PASSWORD ist nicht gesetzt; überspringe die Provisionierung des Administrator-Kontos."
    else
      log_warn "OPSI_ADMIN_PASSWORD is not set; skipping administrator account provisioning."
    fi
    return 0
  fi

  if (( DRY_RUN )); then
    if language_is_de; then
      log_info "[dry-run] Würde sicherstellen, dass der OPSI-Administrator '${admin_user}' im Container '${container_name}' existiert."
    else
      log_info "[dry-run] Would ensure OPSI administrator '${admin_user}' exists inside container '${container_name}'."
    fi
    return 0
  fi

  if ! wait_for_container_running "$container_name" 60; then
    if language_is_de; then
      log_warn "Container ${container_name} läuft nicht; überspringe die Provisionierung des OPSI-Administrator-Kontos."
    else
      log_warn "Container ${container_name} is not running; skipping OPSI administrator provisioning."
    fi
    return 0
  fi

  local password_hash
  if ! password_hash="$(openssl passwd -6 "$admin_password")"; then
    if language_is_de; then
      log_error "Konnte keinen Passwort-Hash für den OPSI-Administrator erzeugen."
    else
      log_error "Failed to generate password hash for the OPSI administrator."
    fi
    exit 1
  fi

  if [[ -z "$password_hash" ]]; then
    if language_is_de; then
      log_error "Der erzeugte Passwort-Hash für den OPSI-Administrator ist leer."
    else
      log_error "Generated password hash for the OPSI administrator is empty."
    fi
    exit 1
  fi

  local user_exists=0
  if docker exec "$container_name" getent passwd "$admin_user" >/dev/null 2>&1; then
    user_exists=1
  fi

  if (( user_exists )); then
    if language_is_de; then
      log_info "Stelle sicher, dass bestehender OPSI-Administrator '${admin_user}' korrekt konfiguriert ist."
    else
      log_info "Ensuring existing OPSI administrator '${admin_user}' is configured correctly."
    fi
  else
    if language_is_de; then
      log_info "Erstelle OPSI-Administrator '${admin_user}' im Container ${container_name}."
    else
      log_info "Creating OPSI administrator '${admin_user}' inside container ${container_name}."
    fi
  fi

  if ! docker exec -i \
      -e OPSI_ADMIN_TARGET_USER="$admin_user" \
      -e OPSI_ADMIN_PASSWORD_HASH="$password_hash" \
      "$container_name" sh <<'EOF'
set -e

user="${OPSI_ADMIN_TARGET_USER}"
hash="${OPSI_ADMIN_PASSWORD_HASH}"

if [ -z "$user" ] || [ -z "$hash" ]; then
  echo "Missing OPSI_ADMIN_TARGET_USER or OPSI_ADMIN_PASSWORD_HASH" >&2
  exit 1
fi

if ! getent group "$user" >/dev/null 2>&1; then
  groupadd "$user"
fi

if ! id -u "$user" >/dev/null 2>&1; then
  useradd -m -s /bin/sh -g "$user" "$user"
else
  usermod -g "$user" "$user" >/dev/null 2>&1 || true
  usermod -s /bin/sh "$user" >/dev/null 2>&1 || true
  if [ ! -d "/home/$user" ]; then
    mkdir -p "/home/$user"
    chown "$user:$user" "/home/$user"
  fi
fi

usermod -p "$hash" "$user"
usermod -U "$user" >/dev/null 2>&1 || true
chage -I -1 -m 0 -M 99999 -E -1 "$user" >/dev/null 2>&1 || true
EOF
  then
    if language_is_de; then
      log_error "Provisionierung des OPSI-Administrator-Kontos im Container ${container_name} ist fehlgeschlagen."
    else
      log_error "Failed to provision the OPSI administrator account inside container ${container_name}."
    fi
    exit 1
  fi
}

main() {
  parse_args "$@"

  select_language
  ensure_env_file
  ensure_directories
  ensure_config_templates
  ensure_dependencies
  ensure_opsiconfd_ssl_assets
  bring_up_stack
  ensure_opsi_admin_account

  log_info "OpsiSuit installer finished"

  if [[ -n "$GENERATED_AGENT_SECRET" ]]; then
    if language_is_de; then
      log_info "Agent-Secret für neue Installationen: ${GENERATED_AGENT_SECRET}"
    else
      log_info "Agent secret for new installations: ${GENERATED_AGENT_SECRET}"
    fi
  fi
}

main "$@"
