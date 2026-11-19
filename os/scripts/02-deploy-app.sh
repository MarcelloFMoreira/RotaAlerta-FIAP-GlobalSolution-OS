#!/usr/bin/env bash
# Instala Node.js LTS, publica a aplicação, configura Nginx e serviços systemd.
set -Eeuo pipefail

SCRIPT_NAME="02-deploy-app"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
OS_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
PROJECT_DIR="$(cd -- "$OS_DIR/.." && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"
load_config
require_root
setup_script_logging "$SCRIPT_NAME"
TMP_DIR=""
cleanup() {
  local rc="$?"
  [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]] && rm -rf "$TMP_DIR"
  on_exit "$rc"
}
trap cleanup EXIT

log INFO "Início do deploy do RotaAlerta. APP_DIR=$APP_DIR"
if [[ ! "$APP_DIR" =~ ^/(opt|srv)/[a-zA-Z0-9._/-]+$ || "$APP_DIR" == *..* ]]; then
  log ERROR "APP_DIR deve estar sob /opt ou /srv e não pode conter espaços ou '..'."
  exit 1
fi
if [[ ! "$APP_PORT" =~ ^[0-9]+$ ]] || (( APP_PORT < 1024 || APP_PORT > 65535 )); then
  log ERROR "APP_PORT deve ser uma porta entre 1024 e 65535."
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends curl ca-certificates gnupg nginx rsync libatomic1

# Node.js 26 é a linha LTS em novembro de 2026. Instalação pelo repositório DEB NodeSource.
CURRENT_NODE_MAJOR="$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)"
if [[ "$CURRENT_NODE_MAJOR" != "26" ]]; then
  log INFO "Instalando Node.js 26 LTS (versão encontrada: ${CURRENT_NODE_MAJOR})."
  TMP_NODE_SETUP="$(mktemp /tmp/nodesource-setup.XXXXXX.sh)"
  curl -fsSL https://deb.nodesource.com/setup_26.x -o "$TMP_NODE_SETUP"
  bash "$TMP_NODE_SETUP"
  rm -f "$TMP_NODE_SETUP"
  apt-get install -y nodejs
fi
NODE_VERSION="$(node --version)"
if [[ ! "$NODE_VERSION" =~ ^v26\. ]]; then
  log ERROR "Versão instalada não é Node.js 26: $NODE_VERSION"
  exit 1
fi
log INFO "Node.js instalado: $NODE_VERSION; npm $(npm --version)"

# Fonte local por padrão; opcionalmente clona o repositório informado no arquivo de configuração.
APP_SOURCE_DIR="$OS_DIR/webapp"
if [[ -n "$APP_REPO_URL" ]]; then
  TMP_DIR="$(mktemp -d /tmp/rotaalerta-repo.XXXXXX)"
  log INFO "Clonando repositório configurado: $APP_REPO_URL"
  git clone --depth 1 "$APP_REPO_URL" "$TMP_DIR/repo"
  APP_SOURCE_DIR="$TMP_DIR/repo/$APP_REPO_SUBDIR"
fi
if [[ ! -f "$APP_SOURCE_DIR/server.js" || ! -d "$APP_SOURCE_DIR/public" ]]; then
  log ERROR "Código web não encontrado em $APP_SOURCE_DIR. Verifique APP_REPO_SUBDIR ou mantenha os arquivos em os/webapp/."
  exit 1
fi

if ! getent group rotaalerta >/dev/null; then
  groupadd --system rotaalerta
fi
if ! id rotaalerta >/dev/null 2>&1; then
  useradd --system --gid rotaalerta --home-dir /nonexistent --shell /usr/sbin/nologin rotaalerta
fi
install -d -o root -g rotaalerta -m 0750 "$APP_DIR"
rsync -a --delete "$APP_SOURCE_DIR/" "$APP_DIR/"
chown -R root:rotaalerta "$APP_DIR"
find "$APP_DIR" -type d -exec chmod 0750 {} \;
find "$APP_DIR" -type f -exec chmod 0640 {} \;
chmod 0750 "$APP_DIR/server.js"
log INFO "Arquivos da aplicação publicados em $APP_DIR"

install -d -o root -g rotaalerta -m 2775 /var/log/rotaalerta
install -d -o root -g root -m 0750 /etc/rotaalerta
if [[ ! -f /etc/rotaalerta/rotaalerta.env ]]; then
  cat > /etc/rotaalerta/rotaalerta.env <<ENVVARS
NODE_ENV=production
HOST=127.0.0.1
PORT=$APP_PORT
LOG_FILE=/var/log/rotaalerta/app.log
MONITOR_INTERVAL=$MONITOR_INTERVAL
CPU_THRESHOLD=$CPU_THRESHOLD
MEMORY_THRESHOLD=$MEMORY_THRESHOLD
DISK_THRESHOLD=$DISK_THRESHOLD
ENVVARS
  chmod 0640 /etc/rotaalerta/rotaalerta.env
  chown root:rotaalerta /etc/rotaalerta/rotaalerta.env
else
  log INFO "Arquivo /etc/rotaalerta/rotaalerta.env já existe; preservando configurações locais."
  set -a
  # shellcheck disable=SC1091
  source /etc/rotaalerta/rotaalerta.env
  set +a
  APP_PORT="${PORT:-$APP_PORT}"
fi
if [[ ! "$APP_PORT" =~ ^[0-9]+$ ]] || (( APP_PORT < 1024 || APP_PORT > 65535 )); then
  log ERROR "PORT inválida no arquivo /etc/rotaalerta/rotaalerta.env."
  exit 1
fi
touch /var/log/rotaalerta/app.log
chown rotaalerta:rotaalerta /var/log/rotaalerta/app.log
chmod 0640 /var/log/rotaalerta/app.log

# Copia o monitor independente para o diretório do serviço.
install -d -o root -g root -m 0755 "$APP_DIR/ops/scripts"
install -o root -g root -m 0750 "$SCRIPT_DIR/03-monitor.sh" "$APP_DIR/ops/scripts/03-monitor.sh"

# Renderiza os templates do systemd com os caminhos efetivos.
sed "s|@APP_DIR@|$APP_DIR|g" "$OS_DIR/systemd/rotaalerta.service" > /etc/systemd/system/rotaalerta.service
sed "s|@APP_DIR@|$APP_DIR|g" "$OS_DIR/systemd/rotaalerta-monitor.service" > /etc/systemd/system/rotaalerta-monitor.service
chmod 0644 /etc/systemd/system/rotaalerta.service /etc/systemd/system/rotaalerta-monitor.service

# Nginx publica HTTP na porta 80 e encaminha ao Node em localhost.
sed "s|@APP_PORT@|$APP_PORT|g" "$OS_DIR/nginx/rotaalerta.conf" > /etc/nginx/sites-available/rotaalerta
chmod 0644 /etc/nginx/sites-available/rotaalerta
ln -sfn /etc/nginx/sites-available/rotaalerta /etc/nginx/sites-enabled/rotaalerta
install -o root -g root -m 0644 "$OS_DIR/logrotate/rotaalerta" /etc/logrotate.d/rotaalerta
if [[ -L /etc/nginx/sites-enabled/default ]]; then
  rm -f /etc/nginx/sites-enabled/default
fi
nginx -t

systemctl daemon-reload
systemctl enable rotaalerta.service rotaalerta-monitor.service nginx.service
systemctl restart rotaalerta.service
systemctl restart rotaalerta-monitor.service
systemctl reload nginx || systemctl restart nginx

if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q 'Status: active'; then
  ufw allow 80/tcp
  ufw allow 443/tcp
  log INFO "Regras HTTP/HTTPS confirmadas no UFW ativo."
fi

log INFO "Aguardando health check da aplicação na porta $APP_PORT."
for attempt in $(seq 1 15); do
  if curl --silent --fail "http://127.0.0.1:$APP_PORT/api/health" >/dev/null; then
    break
  fi
  sleep 2
done
if ! curl --silent --fail "http://127.0.0.1:$APP_PORT/api/health"; then
  log ERROR "Health check falhou. Consulte: journalctl -u rotaalerta.service -n 80 --no-pager"
  exit 1
fi
printf '\n'
if ! curl --silent --fail http://127.0.0.1/ | grep -q 'RotaAlerta'; then
  log ERROR "Nginx não retornou a página web esperada em http://127.0.0.1/."
  exit 1
fi

log INFO "Serviços ativos:"
systemctl --no-pager --full status rotaalerta.service | sed -n '1,9p'
systemctl --no-pager --full status rotaalerta-monitor.service | sed -n '1,9p'
systemctl --no-pager --full status nginx.service | sed -n '1,7p'
log INFO "Deploy concluído. Descubra o IP com: hostname -I"
