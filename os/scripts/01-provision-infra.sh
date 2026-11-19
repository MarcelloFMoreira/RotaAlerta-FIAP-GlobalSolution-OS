#!/usr/bin/env bash
# Provisiona hostname, resolução DNS, configuração IP e ferramentas básicas.
set -Eeuo pipefail

SCRIPT_NAME="01-provision-infra"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"
load_config
require_root
setup_script_logging "$SCRIPT_NAME"
trap 'on_exit $?' EXIT

log INFO "Início do provisionamento de infraestrutura. Configuração: $CONFIG_FILE"

if [[ ! -r /etc/os-release ]]; then
  log ERROR "Não foi possível identificar a distribuição Linux."
  exit 1
fi
# shellcheck disable=SC1091
source /etc/os-release
if [[ "${ID:-}" != "ubuntu" ]]; then
  log ERROR "Distribuição detectada: ${PRETTY_NAME:-desconhecida}. Este script foi preparado para Ubuntu."
  exit 1
fi
log INFO "Sistema detectado: ${PRETTY_NAME:-Ubuntu}"

if [[ ! "$HOSTNAME_TARGET" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]{0,62}$ ]]; then
  log ERROR "HOSTNAME_TARGET inválido: $HOSTNAME_TARGET"
  exit 1
fi
hostnamectl set-hostname "$HOSTNAME_TARGET"
if grep -qE '^127\.0\.1\.1[[:space:]]' /etc/hosts; then
  sed -i -E "s/^127\.0\.1\.1[[:space:]].*/127.0.1.1\t$HOSTNAME_TARGET/" /etc/hosts
else
  printf '127.0.1.1\t%s\n' "$HOSTNAME_TARGET" >> /etc/hosts
fi
log INFO "Hostname configurado: $HOSTNAME_TARGET"

log INFO "Atualizando índice APT e instalando ferramentas de administração."
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
  ca-certificates curl git gnupg jq dnsutils iproute2 net-tools \
  htop sysstat ufw netplan.io systemd-resolved rsync python3-yaml

# Identifica a interface pela rota default, sem presumir eth0/ens33.
if [[ "$NET_IFACE" == "auto" || -z "$NET_IFACE" ]]; then
  NET_IFACE="$(ip -o route show default 2>/dev/null | awk 'NR==1 {print $5}')"
fi
if [[ -z "$NET_IFACE" || ! "$NET_IFACE" =~ ^[a-zA-Z0-9_.:-]+$ ]]; then
  log ERROR "Não foi possível identificar uma interface de rede. Confira: ip -br link"
  exit 1
fi
if ! ip link show "$NET_IFACE" >/dev/null 2>&1; then
  log ERROR "A interface $NET_IFACE não existe. Interfaces: $(ip -br link | tr '\n' '; ')"
  exit 1
fi
log INFO "Interface de rede identificada: $NET_IFACE"

# DNS persistente via systemd-resolved. O arquivo dedicado preserva os demais ajustes.
install -d -m 0755 /etc/systemd/resolved.conf.d
IFS=',' read -r -a DNS_LIST <<< "$DNS_SERVERS"
if [[ "${#DNS_LIST[@]}" -lt 1 ]]; then
  log ERROR "DNS_SERVERS está vazio."
  exit 1
fi
for dns in "${DNS_LIST[@]}"; do
  if [[ ! "$dns" =~ ^[0-9a-fA-F:.]+$ ]]; then
    log ERROR "Endereço DNS inválido: $dns"
    exit 1
  fi
done
{
  printf '[Resolve]\nDNS='
  printf '%s ' "${DNS_LIST[@]}"
  printf '\nDomains=~.\nFallbackDNS=9.9.9.9 149.112.112.112\n'
} > /etc/systemd/resolved.conf.d/rotaalerta.conf
systemctl enable --now systemd-resolved
systemctl restart systemd-resolved
log INFO "DNS persistente configurado: ${DNS_LIST[*]}"

# DHCP é o padrão mais seguro para VMs. A configuração estática é opcional e explícita.
case "${NETWORK_MODE,,}" in
  dhcp)
    log INFO "NETWORK_MODE=dhcp: preservando a configuração IP DHCP existente no Netplan."
    ;;
  static)
    if [[ -z "${STATIC_IP_CIDR:-}" || -z "${DEFAULT_GATEWAY:-}" ]]; then
      log ERROR "Para NETWORK_MODE=static, preencha STATIC_IP_CIDR e DEFAULT_GATEWAY no arquivo de configuração."
      exit 1
    fi
    if [[ ! "$STATIC_IP_CIDR" =~ ^[0-9a-fA-F:.]+/[0-9]{1,3}$ || ! "$DEFAULT_GATEWAY" =~ ^[0-9a-fA-F:.]+$ ]]; then
      log ERROR "STATIC_IP_CIDR ou DEFAULT_GATEWAY não passou na validação básica."
      exit 1
    fi
    NETPLAN_FILE=/etc/netplan/99-rotaalerta.yaml
    if [[ -f "$NETPLAN_FILE" ]]; then
      cp -a "$NETPLAN_FILE" "$NETPLAN_FILE.backup.$(date +%Y%m%d%H%M%S)"
    fi
    # Reutiliza o ID lógico existente no Netplan para que este arquivo seja
    # mesclado à definição da mesma interface, em vez de criar uma segunda NIC.
    NETPLAN_ID="$(python3 - "$NET_IFACE" <<'PYNETPLAN'
import glob, sys, yaml
iface = sys.argv[1]
found = None
for filename in sorted(glob.glob('/etc/netplan/*.yaml')):
    try:
        with open(filename, encoding='utf-8') as stream:
            document = yaml.safe_load(stream) or {}
    except Exception:
        continue
    ethernet = (document.get('network') or {}).get('ethernets') or {}
    for device_id, settings in ethernet.items():
        settings = settings or {}
        match_name = (settings.get('match') or {}).get('name')
        if device_id == iface or match_name == iface:
            found = str(device_id)
            break
    if found:
        break
print(found or '')
PYNETPLAN
)"
    if [[ -z "$NETPLAN_ID" ]]; then
      NETPLAN_ID=rotaalerta
      log WARN "Nenhuma definição existente para $NET_IFACE foi encontrada; será criado um ID Netplan com match name."
    fi
    if [[ ! "$NETPLAN_ID" =~ ^[a-zA-Z0-9_.:-]+$ ]]; then
      log ERROR "ID Netplan detectado é inválido: $NETPLAN_ID"
      exit 1
    fi
    {
      printf 'network:\n  version: 2\n  ethernets:\n    "%s":\n' "$NETPLAN_ID"
      if [[ "$NETPLAN_ID" == "rotaalerta" ]]; then
        printf '      match:\n        name: "%s"\n' "$NET_IFACE"
      fi
      printf '      dhcp4: false\n'
      printf '      addresses: ["%s"]\n' "$STATIC_IP_CIDR"
      printf '      routes:\n        - to: default\n          via: "%s"\n' "$DEFAULT_GATEWAY"
      printf '      nameservers:\n        addresses: ['
      for index in "${!DNS_LIST[@]}"; do
        [[ "$index" -gt 0 ]] && printf ', '
        printf '"%s"' "${DNS_LIST[$index]}"
      done
      printf ']\n'
    } > "$NETPLAN_FILE"
    chmod 0600 "$NETPLAN_FILE"
    log WARN "Aplicando IP estático em $NET_IFACE. Em acesso SSH, confirme os parâmetros para não perder conectividade."
    netplan generate
    netplan apply
    log INFO "Netplan estático aplicado. Arquivo: $NETPLAN_FILE"
    ;;
  *)
    log ERROR "NETWORK_MODE deve ser dhcp ou static (valor atual: $NETWORK_MODE)."
    exit 1
    ;;
esac

if is_yes "$ENABLE_UFW"; then
  log WARN "Habilitando UFW. Portas liberadas: SSH ($SSH_PORT/tcp), HTTP (80/tcp) e HTTPS (443/tcp)."
  if [[ ! "$SSH_PORT" =~ ^[0-9]+$ ]] || (( SSH_PORT < 1 || SSH_PORT > 65535 )); then
    log ERROR "SSH_PORT inválida: $SSH_PORT"
    exit 1
  fi
  ufw allow "$SSH_PORT/tcp"
  ufw allow 80/tcp
  ufw allow 443/tcp
  ufw --force enable
  ufw status verbose
else
  log INFO "UFW não foi habilitado (ENABLE_UFW=$ENABLE_UFW)."
fi

log INFO "Resumo de rede:"
ip -br address show "$NET_IFACE"
ip route show default
resolvectl status "$NET_IFACE" || resolvectl status || true
log INFO "Teste de DNS:"
if getent ahosts ubuntu.com >/dev/null; then
  log INFO "Resolução DNS funcional para ubuntu.com."
else
  log WARN "Não foi possível resolver ubuntu.com. Verifique DNS e conectividade externa."
fi
log INFO "Provisionamento de infraestrutura finalizado."
