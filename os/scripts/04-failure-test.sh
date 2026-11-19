#!/usr/bin/env bash
# Teste de falha e recuperação do RotaAlerta (gera evidência para a avaliação).
# Uso: sudo bash os/scripts/04-failure-test.sh [app] [monitor] [stress]


set -Eeuo pipefail


SCRIPT_NAME="04-failure-test"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"


load_config
require_root
setup_script_logging "$SCRIPT_NAME"


ENV_FILE="/etc/rotaalerta/rotaalerta.env"
ENV_BACKUP=""
if [[ -r "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi


APP_UNIT="rotaalerta.service"
MON_UNIT="rotaalerta-monitor.service"
HEALTH_URL="http://127.0.0.1:${PORT:-$APP_PORT}/api/health"
MONITOR_LOG="$LOG_DIR/monitor.log"
DISK_FILE="/var/tmp/rotaalerta-stress-disk.bin"
EVID_DIR="${EVID_DIR:-$OS_DIR/evidencias}"
REPORT="$EVID_DIR/teste-falha-$(date +%Y%m%d-%H%M%S).txt"
FAILS=0
RESULTS=()
LOAD_PIDS=()


install -d -m 0755 "$EVID_DIR"
: > "$REPORT"


note() {
  log INFO "$*"
  printf '%s %s\n' "$(date --iso-8601=seconds)" "$*" >> "$REPORT"
}


show() {
  printf '$ %s\n' "$*" | tee -a "$REPORT"
  "$@" 2>&1 | tee -a "$REPORT" || true
}


record() {
  RESULTS+=("$1|$2|$3")
  note "RESULTADO $1: $2 - $3"
  if [[ "$2" == "FALHOU" ]]; then
    FAILS=$((FAILS + 1))
  fi
}


is_uint() { [[ "${1:-}" =~ ^[0-9]+$ ]]; }
health_ok() { curl --silent --fail --max-time 3 "$HEALTH_URL" >/dev/null 2>&1; }
main_pid() { systemctl show -p MainPID --value "$1"; }
restarts() { systemctl show -p NRestarts --value "$1"; }
mem_available_kib() { awk '/^MemAvailable:/ {print $2}' /proc/meminfo; }


log_lines() {
  if [[ -f "$MONITOR_LOG" ]]; then wc -l < "$MONITOR_LOG"; else echo 0; fi
}


monitor_log_since() { tail -n "+$(($1 + 1))" "$MONITOR_LOG"; }
monitor_logged_start() { grep -aq 'Monitor iniciado' < <(monitor_log_since "$1"); }


wait_for() {
  local limit="$1" i
  shift
  for ((i = 0; i < limit; i++)); do
    if "$@"; then return 0; fi
    sleep 1
  done
  return 1
}


wait_for_alert() {
  local start_line="$1" pattern="$2" max_wait=$((MONITOR_INTERVAL * 2 + 15)) waited
  for ((waited = 0; waited < max_wait; waited++)); do
    if grep -aq "$pattern" < <(monitor_log_since "$start_line"); then
      sleep 1
      return 0
    fi
    sleep 1
  done
  return 1
}


stop_load() {
  local pid
  for pid in "${LOAD_PIDS[@]:-}"; do
    if [[ -n "$pid" ]]; then
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
    fi
  done
  LOAD_PIDS=()
  rm -f "$DISK_FILE"
}


restore_env() {
  if [[ -n "$ENV_BACKUP" && -f "$ENV_BACKUP" ]]; then
    mv -f "$ENV_BACKUP" "$ENV_FILE"
    chmod 0640 "$ENV_FILE"
    chown root:rotaalerta "$ENV_FILE"
    ENV_BACKUP=""
    systemctl restart "$MON_UNIT" 2>/dev/null || true
  fi
}


cleanup() {
  local rc="$?"
  stop_load
  restore_env
  if [[ -n "${SUDO_USER:-}" && -d "$EVID_DIR" ]]; then
    chown -R "$SUDO_USER:" "$EVID_DIR" 2>/dev/null || true
  fi
  on_exit "$rc"
}


trap cleanup EXIT
trap 'exit 130' INT TERM


test_app() {
  note "=== TESTE 1: queda do processo Node (SIGKILL) e recuperação pelo systemd ==="
  if ! systemctl is-active --quiet "$APP_UNIT" || ! health_ok; then
    record "app-recuperacao" "FALHOU" "pré-condição: $APP_UNIT inativo ou sem health check em $HEALTH_URL"
    return 0
  fi


  local pid_before pid_after restarts_before restarts_after t0 elapsed
  pid_before="$(main_pid "$APP_UNIT")"
  restarts_before="$(restarts "$APP_UNIT")"
  show systemctl show "$APP_UNIT" -p Restart -p RestartUSec -p NRestarts
  note "Estado inicial: MainPID=$pid_before NRestarts=$restarts_before; health check OK."
  note "Injetando falha: systemctl kill --signal=SIGKILL $APP_UNIT"
  t0=$SECONDS
  systemctl kill --signal=SIGKILL "$APP_UNIT"
  sleep 1
  show systemctl status "$APP_UNIT" --no-pager --lines=0


  if wait_for 40 health_ok; then
    elapsed=$((SECONDS - t0))
    pid_after="$(main_pid "$APP_UNIT")"
    restarts_after="$(restarts "$APP_UNIT")"
    note "Aplicação voltou a responder em ${elapsed}s: MainPID=$pid_after NRestarts=$restarts_after."
    show curl --silent --max-time 3 "$HEALTH_URL"
    printf '\n' | tee -a "$REPORT"
    if curl --silent --fail --max-time 3 http://127.0.0.1/ >/dev/null; then
      note "Nginx na porta 80 também voltou a servir a página."
    fi
    show journalctl -u "$APP_UNIT" -n 8 --no-pager -o short-iso
    if [[ "$pid_after" != "$pid_before" && "$pid_after" != "0" ]]; then
      record "app-recuperacao" "PASSOU" "PID $pid_before -> $pid_after; recuperado em ${elapsed}s pelo systemd"
    else
      record "app-recuperacao" "FALHOU" "PID não mudou; a falha pode não ter sido injetada"
    fi
  else
    show journalctl -u "$APP_UNIT" -n 15 --no-pager -o short-iso
    record "app-recuperacao" "FALHOU" "a aplicação não voltou em 40s"
  fi
}


test_monitor() {
  note "=== TESTE 2: queda do serviço de monitoramento (SIGKILL) ==="
  if ! systemctl is-active --quiet "$MON_UNIT"; then
    record "monitor-recuperacao" "FALHOU" "pré-condição: $MON_UNIT inativo"
    return 0
  fi


  local pid_before pid_after lines_before t0 elapsed
  pid_before="$(main_pid "$MON_UNIT")"
  lines_before="$(log_lines)"
  show systemctl show "$MON_UNIT" -p Restart -p RestartUSec -p StartLimitIntervalUSec -p NRestarts
  note "Estado inicial: MainPID=$pid_before."
  note "Injetando falha: systemctl kill --signal=SIGKILL $MON_UNIT"
  t0=$SECONDS
  systemctl kill --signal=SIGKILL "$MON_UNIT"
  sleep 1
  show systemctl status "$MON_UNIT" --no-pager --lines=0


  if wait_for 45 monitor_logged_start "$lines_before"; then
    elapsed=$((SECONDS - t0))
    pid_after="$(main_pid "$MON_UNIT")"
    note "Monitor reiniciado em ${elapsed}s: MainPID=$pid_after. Novas linhas de monitor.log:"
    monitor_log_since "$lines_before" | tee -a "$REPORT"
    show journalctl -u "$MON_UNIT" -n 6 --no-pager -o short-iso
    if [[ "$pid_after" != "$pid_before" && "$pid_after" != "0" ]]; then
      record "monitor-recuperacao" "PASSOU" "PID $pid_before -> $pid_after; voltou a logar em ${elapsed}s"
    else
      record "monitor-recuperacao" "FALHOU" "o PID não mudou; a falha pode não ter sido injetada"
    fi
  else
    show journalctl -u "$MON_UNIT" -n 15 --no-pager -o short-iso
    record "monitor-recuperacao" "FALHOU" "o monitor não voltou a logar em 45s"
  fi
}


check_alert() {
  if [[ "$2" -ne 1 ]]; then
    record "$1" "PULADO" "carga não aplicada neste ambiente"
  elif grep -aq "$3" <<<"$4"; then
    record "$1" "PASSOU" "monitor registrou ALERTA: $3"
  else
    record "$1" "FALHOU" "nenhuma linha de ALERTA com '$3' em monitor.log"
  fi
}


test_stress() {
  note "=== TESTE 3: carga controlada de CPU, disco e RAM para disparar alertas ==="
  if ! systemctl is-active --quiet "$MON_UNIT"; then
    record "alertas-recursos" "FALHOU" "pré-condição: $MON_UNIT inativo"
    return 0
  fi


  local lines_before seg_start cores i waited cpu_on=1 mem_on=0 disk_on=0
  local target used_b avail_b basis need mem_total_kib mem_avail_kib keep_kib alloc_kib mem_goal_kib mem_pid eff_mem_thresh
  lines_before="$(log_lines)"


  # 1) CPU
  seg_start="$(log_lines)"
  cores="$(nproc)"
  for ((i = 0; i < cores; i++)); do
    yes >/dev/null &
    LOAD_PIDS+=("$!")
  done
  note "CPU: $cores processo(s) 'yes' ativos. Aguardando alerta do monitor..."
  wait_for_alert "$seg_start" 'CPU acima do limite' || true
  stop_load
  check_alert "alerta-cpu" "$cpu_on" 'CPU acima do limite' "$(monitor_log_since "$seg_start")"


  # 2) Disco
  seg_start="$(log_lines)"
  if [[ "${STRESS_DISK:-yes}" != "no" ]] && is_uint "$DISK_THRESHOLD" && ((DISK_THRESHOLD + 2 <= 95)); then
    target=$((DISK_THRESHOLD + 2))
    read -r used_b avail_b < <(df -B1 --output=used,avail / | awk 'NR==2 {print $1, $2}')
    basis=$((used_b + avail_b))
    need=$((basis * target / 100 - used_b))
    if ((need <= 0)) || fallocate -l "$need" "$DISK_FILE"; then
      disk_on=1
      note "DISCO: uso levado a ~${target}%. Aguardando alerta do monitor..."
      wait_for_alert "$seg_start" 'Disco da raiz acima do limite' || true
      stop_load
    fi
  fi
  check_alert "alerta-disco" "$disk_on" 'Disco da raiz acima do limite' "$(monitor_log_since "$seg_start")"


  # 3) RAM
  seg_start="$(log_lines)"
  if [[ "${STRESS_MEM:-yes}" != "no" ]] && command -v python3 >/dev/null 2>&1 && is_uint "$MEMORY_THRESHOLD"; then
    mem_total_kib="$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)"
    mem_avail_kib="$(mem_available_kib)"
    eff_mem_thresh="$MEMORY_THRESHOLD"
    target=$((eff_mem_thresh + 2))
    keep_kib=$((mem_total_kib * (100 - target) / 100))
    alloc_kib=$((mem_avail_kib - keep_kib))


    if ((alloc_kib > 2097152)) && [[ -f "$ENV_FILE" ]]; then
      ENV_BACKUP="$(mktemp /tmp/rotaalerta.env.XXXXXX)"
      cp -p "$ENV_FILE" "$ENV_BACKUP"
      eff_mem_thresh=30
      target=35
      sed -i "s/^MEMORY_THRESHOLD=.*/MEMORY_THRESHOLD=$eff_mem_thresh/" "$ENV_FILE"
      systemctl restart "$MON_UNIT"
      sleep 2
      mem_avail_kib="$(mem_available_kib)"
      keep_kib=$((mem_total_kib * (100 - target) / 100))
      alloc_kib=$((mem_avail_kib - keep_kib))
    fi


    if ((alloc_kib > 0 && keep_kib >= 153600)); then
      python3 - "$((alloc_kib * 1024))" <<'PYMEM' &
import sys, time
try:
    with open("/proc/self/oom_score_adj", "w") as fh:
        fh.write("1000")
except OSError:
    pass
block = b"a" * int(sys.argv[1])
time.sleep(300)
PYMEM
      mem_pid="$!"
      LOAD_PIDS+=("$mem_pid")
      mem_goal_kib=$((mem_total_kib * (100 - eff_mem_thresh - 1) / 100))
      for ((waited = 0; waited < 30; waited++)); do
        if (($(mem_available_kib) <= mem_goal_kib)); then
          mem_on=1
          break
        fi
        sleep 1
      done
      if ((mem_on == 1)); then
        note "RAM: $((alloc_kib / 1024)) MiB alocados (alvo ~${target}%). Aguardando alerta do monitor..."
        wait_for_alert "$seg_start" 'Memória RAM acima do limite' || true
      fi
      stop_load
    fi
    check_alert "alerta-memoria" "$mem_on" 'Memória RAM acima do limite' "$(monitor_log_since "$seg_start")"
    restore_env
  else
    check_alert "alerta-memoria" "0" 'Memória RAM acima do limite' ""
  fi


  if health_ok; then
    record "app-sob-carga" "PASSOU" "health check respondeu durante e após a carga"
  else
    record "app-sob-carga" "FALHOU" "health check não respondeu"
  fi


  note "Linhas do monitor durante o teste:"
  grep -aE 'ALERTA|Recursos' <<<"$(monitor_log_since "$lines_before")" | tee -a "$REPORT" || true
  show journalctl -t rotaalerta-monitor -n 10 --no-pager -o short-iso
}


TESTS=("$@")
if [[ ${#TESTS[@]} -eq 0 ]]; then
  TESTS=(app monitor stress)
fi


for t in "${TESTS[@]}"; do
  case "$t" in
    app | monitor | stress) ;;
    *)
      log ERROR "Teste desconhecido: $t (use: app monitor stress)"
      exit 2
      ;;
  esac
done


note "Início do teste de falha. Testes: ${TESTS[*]}. Evidência: $REPORT"
for t in "${TESTS[@]}"; do
  case "$t" in
    app) test_app ;;
    monitor) test_monitor ;;
    stress) test_stress ;;
  esac
done


note "=== RESUMO ==="
for entry in "${RESULTS[@]}"; do
  IFS='|' read -r r_name r_status r_detail <<<"$entry"
  printf '%-22s %-8s %s\n' "$r_name" "$r_status" "$r_detail" | tee -a "$REPORT"
done
note "Evidência salva em: $REPORT"


if ((FAILS > 0)); then
  log ERROR "$FAILS verificação(ões) falharam."
  exit 1
fi
log INFO "Todas as verificações executadas passaram."
