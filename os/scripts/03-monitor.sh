#!/usr/bin/env bash
# Loop de monitoramento de CPU, memória RAM e disco. Projetado para systemd.
set -Eeuo pipefail

SCRIPT_NAME="03-monitor"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
OS_DIR="$(cd -- "$SCRIPT_DIR/.." 2>/dev/null && pwd || true)"
CONFIG_FILE="/etc/rotaalerta/rotaalerta.env"
if [[ ! -f "$CONFIG_FILE" && -n "$OS_DIR" ]]; then
  CONFIG_FILE="$OS_DIR/config/rotaalerta.env"
  [[ -f "$CONFIG_FILE" ]] || CONFIG_FILE="$OS_DIR/config/rotaalerta.env.example"
fi
if [[ -f "$CONFIG_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
  set +a
fi

LOG_DIR="${LOG_DIR:-/var/log/rotaalerta}"
MONITOR_LOG="$LOG_DIR/monitor.log"
MONITOR_INTERVAL="${MONITOR_INTERVAL:-30}"
CPU_THRESHOLD="${CPU_THRESHOLD:-85}"
MEMORY_THRESHOLD="${MEMORY_THRESHOLD:-85}"
DISK_THRESHOLD="${DISK_THRESHOLD:-85}"

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "Execute como root: sudo bash $0" >&2
  exit 1
fi
if [[ ! "$MONITOR_INTERVAL" =~ ^[0-9]+$ ]] || (( MONITOR_INTERVAL < 5 )); then
  echo "MONITOR_INTERVAL precisa ser um inteiro >= 5 segundos." >&2
  exit 1
fi
for threshold in "$CPU_THRESHOLD" "$MEMORY_THRESHOLD" "$DISK_THRESHOLD"; do
  if ! awk -v t="$threshold" 'BEGIN { exit !(t >= 1 && t <= 100) }'; then
    echo "Limiares de monitoramento devem ficar entre 1 e 100." >&2
    exit 1
  fi
done

install -d -m 0750 "$LOG_DIR"
touch "$MONITOR_LOG"
chmod 0640 "$MONITOR_LOG"

write_log() {
  local level="$1"; shift
  local line="$(date --iso-8601=seconds) [$level] $*"
  printf '%s\n' "$line" | tee -a "$MONITOR_LOG"
  if [[ "$level" == "ALERTA" ]] && command -v logger >/dev/null 2>&1; then
    logger -p daemon.warning -t rotaalerta-monitor -- "$*" || true
  fi
}

cpu_snapshot() {
  awk '/^cpu / { total=0; for (i=2; i<=NF; i++) total+=$i; idle=$5+$6; printf "%d %d\n", total, idle; exit }' /proc/stat
}

read -r cpu_total_1 cpu_idle_1 < <(cpu_snapshot)
write_log INFO "Monitor iniciado: intervalo=${MONITOR_INTERVAL}s; limites CPU=${CPU_THRESHOLD}% RAM=${MEMORY_THRESHOLD}% DISCO=${DISK_THRESHOLD}%"

shutdown_monitor() {
  write_log INFO "Monitor encerrado por sinal do sistema."
  exit 0
}
trap shutdown_monitor SIGTERM SIGINT

while true; do
  read -r cpu_total_1 cpu_idle_1 < <(cpu_snapshot)
  sleep 1
  read -r cpu_total_2 cpu_idle_2 < <(cpu_snapshot)
  total_delta=$((cpu_total_2 - cpu_total_1))
  idle_delta=$((cpu_idle_2 - cpu_idle_1))
  if (( total_delta > 0 )); then
    cpu_pct="$(awk -v total="$total_delta" -v idle="$idle_delta" 'BEGIN { printf "%.1f", 100 * (1 - idle / total) }')"
  else
    cpu_pct="0.0"
  fi

  mem_pct="$(free -b | awk '/^Mem:/ { if ($2 > 0) printf "%.1f", 100 * (1 - $7 / $2); else print "0.0" }')"
  disk_pct="$(df -P / | awk 'NR==2 { gsub(/%/, "", $5); print $5 }')"
  [[ -n "$mem_pct" ]] || mem_pct=0
  [[ -n "$disk_pct" ]] || disk_pct=0

  write_log INFO "Recursos: CPU=${cpu_pct}% RAM=${mem_pct}% DISCO_ROOT=${disk_pct}%"
  alert_count=0
  if awk -v v="$cpu_pct" -v t="$CPU_THRESHOLD" 'BEGIN { exit !(v >= t) }'; then
    write_log ALERTA "CPU acima do limite: ${cpu_pct}% (limite ${CPU_THRESHOLD}%)."
    alert_count=$((alert_count + 1))
  fi
  if awk -v v="$mem_pct" -v t="$MEMORY_THRESHOLD" 'BEGIN { exit !(v >= t) }'; then
    write_log ALERTA "Memória RAM acima do limite: ${mem_pct}% (limite ${MEMORY_THRESHOLD}%)."
    alert_count=$((alert_count + 1))
  fi
  if awk -v v="$disk_pct" -v t="$DISK_THRESHOLD" 'BEGIN { exit !(v >= t) }'; then
    write_log ALERTA "Disco da raiz acima do limite: ${disk_pct}% (limite ${DISK_THRESHOLD}%)."
    alert_count=$((alert_count + 1))
  fi
  if (( alert_count == 0 )); then
    : # Sem alertas neste ciclo.
  fi
  sleep "$MONITOR_INTERVAL"
done
