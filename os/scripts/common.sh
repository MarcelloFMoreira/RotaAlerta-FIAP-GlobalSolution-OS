#!/usr/bin/env bash
# Funções compartilhadas de auditoria e carregamento de configuração.

OS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="${CONFIG_FILE:-$OS_DIR/config/rotaalerta.env}"
if [[ ! -f "$CONFIG_FILE" ]]; then
  CONFIG_FILE="$OS_DIR/config/rotaalerta.env.example"
fi

load_config() {
  if [[ -f "$CONFIG_FILE" ]]; then
    # O arquivo é configuração local do projeto (KEY=value), não aceite origem desconhecida.
    set -a
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
    set +a
  fi
  : "${HOSTNAME_TARGET:=rotaalerta-server}"
  : "${NETWORK_MODE:=dhcp}"
  : "${NET_IFACE:=auto}"
  : "${DNS_SERVERS:=1.1.1.1,8.8.8.8}"
  : "${ENABLE_UFW:=no}"
  : "${SSH_PORT:=22}"
  : "${APP_DIR:=/opt/rotaalerta}"
  : "${APP_PORT:=3000}"
  : "${APP_REPO_URL:=}"
  : "${APP_REPO_SUBDIR:=os/webapp}"
  : "${MONITOR_INTERVAL:=30}"
  : "${CPU_THRESHOLD:=85}"
  : "${MEMORY_THRESHOLD:=85}"
  : "${DISK_THRESHOLD:=85}"
  LOG_DIR="${LOG_DIR:-/var/log/rotaalerta}"
  export LOG_DIR
}

require_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    echo "ERRO: execute com sudo: sudo bash $0" >&2
    exit 1
  fi
}

setup_script_logging() {
  local name="$1"
  install -d -m 0750 "$LOG_DIR"
  touch "$LOG_DIR/audit.log" "$LOG_DIR/$name.log"
  chmod 0640 "$LOG_DIR/audit.log" "$LOG_DIR/$name.log"
  SCRIPT_LOG="$LOG_DIR/$name.log"
  AUDIT_LOG="$LOG_DIR/audit.log"
  export SCRIPT_LOG AUDIT_LOG
  exec > >(tee -a "$SCRIPT_LOG") 2>&1
}

log() {
  local level="$1"; shift
  local line
  line="$(date --iso-8601=seconds) [$level] $*"
  printf '%s\n' "$line"
  if [[ -n "${AUDIT_LOG:-}" ]]; then
    printf '%s actor=%s script=%s event=%q\n' \
      "$(date --iso-8601=seconds)" "${SUDO_USER:-root}" "${SCRIPT_NAME:-unknown}" "$*" >> "$AUDIT_LOG"
  fi
}

on_exit() {
  local rc="${1:-0}"
  if [[ "$rc" -eq 0 ]]; then
    log INFO "Execução concluída com sucesso: ${SCRIPT_NAME:-script}"
  else
    log ERROR "Execução encerrada com erro (código $rc): ${SCRIPT_NAME:-script}"
  fi
  return "$rc"
}

is_yes() {
  [[ "${1,,}" == "yes" || "${1,,}" == "sim" || "${1,,}" == "true" || "${1}" == "1" ]]
}
