# RotaAlerta — Operating Systems (FIAP Global Solution 2026.2)

> **Objetivo:** provisionar uma VM Ubuntu Server, publicar uma aplicação web CitizenTech, manter os processos com `systemd` e acompanhar CPU, memória e disco com logs e alertas.
>
> **Prazo da Global Solution no briefing:** 19/11/2026 às 23h55. **Vídeo de Operating Systems:** até 7 minutos.

## 1. O que este módulo entrega

Esta pasta acrescenta uma versão Web leve do RotaAlerta e os componentes de administração Linux solicitados nos slides 35, 36 e 37 do briefing FIAP.

| Critério | Implementação | Evidência/arquivo |
|---|---|---|
| Provisionamento de infra — 2 pts | Hostname, identificação da interface, DNS persistente via `systemd-resolved`, DHCP preservado por padrão ou IP estático via Netplan, pacotes básicos e opção de UFW | `scripts/01-provision-infra.sh`, `/var/log/rotaalerta/01-provision-infra.log` |
| Provisionamento da aplicação — 2 pts | Node.js 26 LTS, Nginx, publicação dos arquivos, configuração do proxy e health check | `scripts/02-deploy-app.sh`, `/var/log/rotaalerta/02-deploy-app.log` |
| Monitoramento de CPU, RAM e disco — 2 pts | Coleta periódica, limiares configuráveis e alertas em log e syslog | `scripts/03-monitor.sh`, `/var/log/rotaalerta/monitor.log` |
| Serviço tolerante a falhas — 1 pt | App e monitor como serviços `systemd`, com `Restart=always` | `systemd/rotaalerta.service`, `systemd/rotaalerta-monitor.service` |
| Auditoria e execução — 1 pt | Log central de eventos, logs individuais e logs do processo | `/var/log/rotaalerta/audit.log`, demais `.log` e `journalctl` |
| Funcionamento da proposta — 2 pts | Interface web + API Node.js com verificação de rota e cenários simulados de alagamento, acidente e Zona Azul | `webapp/`, teste pelo navegador e endpoints REST |

## 2. Arquitetura da solução

```text
Navegador do usuário
       |
       | HTTP :80
       v
     Nginx
       |
       | Proxy reverso para 127.0.0.1:3000
       v
Node.js 26 LTS — RotaAlerta Web
       |-- Frontend: HTML + CSS + JavaScript
       |-- API: GET /api/health
       |-- API: GET /api/status
       |-- API: POST /api/route/check
       `-- Log: /var/log/rotaalerta/app.log

systemd
  |-- rotaalerta.service          (aplicação web)
  `-- rotaalerta-monitor.service  (monitor em loop)

Monitor: CPU + memória RAM + uso de disco da raiz (/)
  `-- /var/log/rotaalerta/monitor.log + syslog (alertas)

Auditoria dos scripts: /var/log/rotaalerta/audit.log
```

### Relação com o aplicativo mobile enviado

O ZIP original contém o aplicativo React Native/Expo do RotaAlerta, direcionado a Android/iOS. O README original informa que o `react-native-maps` utilizado na tela principal não funciona no navegador. Para que a entrega de Operating Systems tenha um componente Web funcional na VM, esta pasta adiciona uma **versão Web demonstrativa complementar**, sem substituir nem remover o projeto mobile.

O frontend Web chama uma API Node.js local. Os cenários de tráfego, alagamento e Zona Azul são **simulados** e identificados na tela; esta demonstração não afirma consultar dados de trânsito ou vagas em tempo real. Isso permite provar a hospedagem e a integração frontend/backend sem depender de chaves de serviços externos.

## 3. Requisitos e premissas

- Ubuntu Server 24.04 ou 26.04 (a configuração foi preparada pensando na VM Ubuntu Server 26.04.1 usada na atividade).
- Usuário com permissão `sudo`.
- Acesso à internet durante a instalação de pacotes e Node.js.
- Conectividade da VM configurada no hypervisor.
- Porta TCP 80 liberada para acessar o site a partir da máquina host/rede.
- Node.js 26 LTS é instalado pelo repositório DEB da NodeSource caso a VM ainda não o tenha. Em novembro de 2026, a linha 26 está em LTS. Consulte a página oficial de releases do Node.js e as instruções NodeSource para Ubuntu 26.04.

Fontes técnicas: [Node.js — Releases](https://nodejs.org/en/about/previous-releases) · [NodeSource — distribuições e Ubuntu 26.04](https://deb.nodesource.com/).

## 4. Preparação dentro da VM Ubuntu

### 4.1 Coloque o repositório dentro da VM

Se o projeto já estiver no Ubuntu, entre na pasta raiz que contém `os/`. Caso esteja no Windows, você pode compartilhar uma pasta com a VM ou clonar o repositório Git:

```bash
git clone URL_DO_REPOSITORIO rotaalerta
cd rotaalerta
```

Se você recebeu o ZIP, extraia-o e entre na pasta `rotaalerta-main`.

### 4.2 Configure os parâmetros

```bash
cp os/config/rotaalerta.env.example os/config/rotaalerta.env
nano os/config/rotaalerta.env
```

O padrão é apropriado para a maioria das VMs:

```ini
HOSTNAME_TARGET=rotaalerta-server
NETWORK_MODE=dhcp
NET_IFACE=auto
STATIC_IP_CIDR=
DEFAULT_GATEWAY=
DNS_SERVERS=1.1.1.1,8.8.8.8
ENABLE_UFW=no
SSH_PORT=22
APP_DIR=/opt/rotaalerta
APP_PORT=3000
APP_REPO_URL=
APP_REPO_SUBDIR=os/webapp
MONITOR_INTERVAL=30
CPU_THRESHOLD=85
MEMORY_THRESHOLD=85
DISK_THRESHOLD=85
```

**Rede DHCP (recomendado para a primeira execução):** o script identifica a interface pela rota default, preserva o DHCP já configurado pelo Ubuntu/hipervisor e configura DNS persistente via `systemd-resolved`. O IP atual será mostrado no resumo final.

**Rede com IP estático (somente se você souber os dados da rede):** altere `NETWORK_MODE=static`, informe a interface real, o IP/CIDR e o gateway. Exemplo ilustrativo — **não copie sem adaptar à sua rede**:

```ini
NETWORK_MODE=static
NET_IFACE=enp0s3
STATIC_IP_CIDR=192.168.1.150/24
DEFAULT_GATEWAY=192.168.1.1
DNS_SERVERS=1.1.1.1,8.8.8.8
```

Para descobrir os valores corretos antes de editar:

```bash
ip -br link
ip -br address
ip route show default
resolvectl status
```

A aplicação de IP estático pode interromper uma sessão SSH se o endereço/gateway estiverem incorretos. Em uma VM acessada pelo console do hypervisor, é mais fácil recuperar a configuração. O modo DHCP não reescreve seus arquivos Netplan.

**Firewall:** `ENABLE_UFW=no` é o padrão para não bloquear acesso remoto acidentalmente. Para habilitar UFW, confirme antes a porta SSH, configure `SSH_PORT` (padrão 22) e então use `ENABLE_UFW=yes`. O script libera a porta SSH informada em `SSH_PORT` (padrão 22), HTTP e HTTPS.

### 4.3 Dê permissão aos scripts

```bash
chmod +x os/scripts/*.sh
```

## 5. Provisionamento da infraestrutura

Execute a partir da raiz do projeto:

```bash
sudo bash os/scripts/01-provision-infra.sh
```

O script faz, em sequência:

1. Confere se o sistema é Ubuntu.
2. Define o hostname e atualiza `/etc/hosts`.
3. Atualiza o APT e instala ferramentas básicas (`curl`, `git`, `jq`, `dnsutils`, `iproute2`, `htop`, `sysstat`, `ufw`, Netplan, `systemd-resolved` e outras).
4. Descobre a interface de rede ativa.
5. Persiste os servidores DNS em `/etc/systemd/resolved.conf.d/rotaalerta.conf`.
6. Mantém DHCP ou aplica o IP estático explicitamente configurado.
7. Mostra interface, IP, rota default e estado do DNS.
8. Opcionalmente habilita UFW.

Valide:

```bash
hostnamectl
ip -br address
ip route show default
resolvectl status
getent hosts ubuntu.com
```

Logs:

```bash
sudo tail -n 40 /var/log/rotaalerta/01-provision-infra.log
sudo tail -n 40 /var/log/rotaalerta/audit.log
```

## 6. Deploy automatizado da aplicação

```bash
sudo bash os/scripts/02-deploy-app.sh
```

O script:

- instala Nginx, `rsync`, `libatomic1` e Node.js 26 LTS;
- copia `os/webapp/` para `/opt/rotaalerta` (ou o valor configurado em `APP_DIR`);
- cria o usuário de sistema sem login `rotaalerta`;
- cria `/etc/rotaalerta/rotaalerta.env` se ainda não existir;
- instala os serviços systemd;
- configura Nginx na porta 80 como proxy reverso para Node.js;
- configura rotação diária de logs (`/etc/logrotate.d/rotaalerta`);
- habilita e inicia aplicação, monitor e Nginx;
- executa um health check na API e verifica a página inicial pelo Nginx.

**Clonagem opcional:** para fazer o deploy diretamente de um repositório Git, defina `APP_REPO_URL` e mantenha `APP_REPO_SUBDIR=os/webapp` quando o código estiver na estrutura deste projeto. Sem `APP_REPO_URL`, o script utiliza os arquivos locais já extraídos, que é o fluxo recomendado para a primeira demonstração.

Confira os serviços:

```bash
sudo systemctl status rotaalerta.service
sudo systemctl status rotaalerta-monitor.service
sudo systemctl status nginx.service
```

Descubra o IP da VM:

```bash
hostname -I
```

Abra no navegador do Windows ou de outro dispositivo:

```text
http://IP_DA_VM/
```

Se estiver usando VirtualBox em modo **NAT**, a máquina Windows pode não conseguir acessar diretamente o IP privado do guest. Nesse caso, configure encaminhamento de porta TCP (por exemplo, host `8080` → guest `80`) ou use uma interface em modo Bridge. Com encaminhamento, acesse `http://127.0.0.1:8080/` no Windows.

## 7. Teste funcional da CitizenTech

Na página RotaAlerta:

1. Informe o nome da rotina e origem/destino.
2. Selecione `Rotina normal — sem ocorrências` e clique em **Verificar minha rota**. O backend deve retornar rota sem alertas, atraso de 0 min e disponibilidade demonstrativa de Zona Azul.
3. Selecione `Chuva forte — simular alagamento` e verifique o alerta de alagamento, atraso ilustrativo de 25 min, recomendação e quantidade simulada de vagas.
4. Selecione `Ocorrência — simular acidente` e verifique o alerta alternativo.
5. Observe o indicador `Servidor online` no cabeçalho.

Teste direto da API (dentro do Ubuntu):

```bash
curl -s http://127.0.0.1:3000/api/health | jq
curl -s http://127.0.0.1/api/status | jq
curl -s -X POST http://127.0.0.1/api/route/check \
  -H 'Content-Type: application/json' \
  -d '{"routine":"Faculdade","origin":"Casa","destination":"FIAP","scenario":"flood"}' | jq
```

A porta 3000 é de uso interno da VM; o acesso normal pelo navegador passa pelo Nginx na porta 80.

## 8. Monitoramento contínuo de recursos

O script pode ser executado manualmente para inspeção (encerre com `Ctrl+C`):

```bash
sudo bash os/scripts/03-monitor.sh
```

No deploy, ele também é instalado como serviço de sistema. Para acompanhar a coleta:

```bash
sudo systemctl status rotaalerta-monitor.service
sudo tail -f /var/log/rotaalerta/monitor.log
```

Cada ciclo registra:

- **CPU:** percentual de utilização calculado por duas leituras de `/proc/stat` com intervalo de um segundo.
- **Memória RAM:** percentual utilizado calculado a partir de `free -b` e da memória disponível.
- **Disco:** percentual de uso do filesystem raiz (`/`) via `df -P /`.

Os limites são configuráveis no arquivo `/etc/rotaalerta/rotaalerta.env` (padrão 85%). Quando qualquer limiar é atingido, o script grava uma linha `[ALERTA]` em `monitor.log` e envia a mensagem ao syslog pelo `logger`.

Para alterar frequência ou limites:

```bash
sudo nano /etc/rotaalerta/rotaalerta.env
sudo systemctl restart rotaalerta-monitor.service
```

O intervalo mínimo é 5 segundos; os limiares aceitam valores de 1 a 100.

### Teste de alerta controlado para a gravação

Para gerar um alerta de disco sem encher a VM:

```bash
sudo cp /etc/rotaalerta/rotaalerta.env /etc/rotaalerta/rotaalerta.env.bak
sudo sed -i 's/^DISK_THRESHOLD=.*/DISK_THRESHOLD=1/' /etc/rotaalerta/rotaalerta.env
sudo systemctl restart rotaalerta-monitor.service
sleep 5
sudo tail -n 12 /var/log/rotaalerta/monitor.log
```

Deve aparecer `[ALERTA] Disco da raiz acima do limite...` se o uso real da raiz for igual ou maior que 1%. Ao terminar, **restaure a configuração**:

```bash
sudo mv /etc/rotaalerta/rotaalerta.env.bak /etc/rotaalerta/rotaalerta.env
sudo systemctl restart rotaalerta-monitor.service
```

## 9. Teste de falha e recuperação automática (systemd)

O serviço da aplicação está configurado com `Restart=always` e intervalo de 5 segundos. Para demonstrar a recuperação, mate o processo controlado pelo systemd:

```bash
sudo systemctl show rotaalerta.service -p ActiveState -p NRestarts
sudo systemctl kill --signal=SIGKILL rotaalerta.service
sleep 7
sudo systemctl status rotaalerta.service
sudo systemctl show rotaalerta.service -p ActiveState -p NRestarts
curl -I http://127.0.0.1/
```

Resultado esperado: o serviço volta para `active (running)`, o contador `NRestarts` aumenta e o site continua respondendo. O teste provoca uma interrupção momentânea; faça-o antes da gravação ou durante o bloco de demonstração previsto.

Para demonstrar recuperação do monitor, pode-se repetir com `sudo systemctl kill --signal=SIGKILL rotaalerta-monitor.service`, aguardar 12 segundos e consultar o status.

## 10. Logs de auditoria e execução

| Arquivo/comando | Finalidade |
|---|---|
| `/var/log/rotaalerta/audit.log` | Eventos de execução dos scripts, ator, script e resultado |
| `/var/log/rotaalerta/01-provision-infra.log` | Saída do provisionamento de infraestrutura |
| `/var/log/rotaalerta/02-deploy-app.log` | Saída do deploy, instalação e health checks |
| `/var/log/rotaalerta/monitor.log` | Amostras de recursos e alertas de limiar |
| `/var/log/rotaalerta/app.log` | Eventos da API e inicialização/encerramento da aplicação |
| `journalctl -u rotaalerta.service` | Saída do processo Node.js pelo systemd |
| `journalctl -u rotaalerta-monitor.service` | Saída do processo de monitoramento pelo systemd |
| `/var/log/nginx/rotaalerta-access.log` | Requisições HTTP recebidas pelo Nginx |
| `/var/log/nginx/rotaalerta-error.log` | Erros de proxy/HTTP do Nginx |

Comandos úteis para coletar evidências:

```bash
sudo tail -n 30 /var/log/rotaalerta/audit.log
sudo tail -n 30 /var/log/rotaalerta/monitor.log
sudo tail -n 30 /var/log/rotaalerta/app.log
sudo journalctl -u rotaalerta.service -n 30 --no-pager
sudo journalctl -u rotaalerta-monitor.service -n 30 --no-pager
sudo tail -n 20 /var/log/nginx/rotaalerta-access.log
```

O `logrotate` é configurado para rotação diária, 14 arquivos históricos e compressão, evitando crescimento ilimitado dos logs locais.

## 11. Resolução de problemas

**Página não abre no navegador**

```bash
hostname -I
sudo systemctl status nginx rotaalerta
sudo nginx -t
sudo ss -lntp | grep -E ':80|:3000'
curl -I http://127.0.0.1/
curl -s http://127.0.0.1:3000/api/health
```

Confirme também o modo de rede da VM, firewall do Ubuntu e encaminhamento NAT/Bridge do hypervisor.

**Node.js não iniciou**

```bash
node --version
sudo journalctl -u rotaalerta.service -n 80 --no-pager
sudo cat /etc/rotaalerta/rotaalerta.env
```

**Monitor sem log**

```bash
sudo systemctl status rotaalerta-monitor.service
sudo journalctl -u rotaalerta-monitor.service -n 80 --no-pager
sudo ls -l /var/log/rotaalerta/
```

**DNS não resolve**

```bash
resolvectl status
systemctl status systemd-resolved
getent hosts ubuntu.com
```

## 12. Roteiro sugerido para o vídeo (até 7 minutos)

| Tempo | O que mostrar | O que falar |
|---|---|---|
| 0:00–0:25 | Apresentação do RotaAlerta e objetivo | “O RotaAlerta ajuda estudantes e trabalhadores a antecipar imprevistos da rota habitual, reduzindo surpresas no deslocamento.” |
| 0:25–1:25 | Terminal: executar `01-provision-infra.sh`; mostrar hostname, `ip -br address`, rota e `resolvectl status` | “O primeiro script prepara o Ubuntu, configura o hostname, identifica a interface, mantém DHCP ou aplica IP estático configurado e persiste DNS.” |
| 1:25–2:20 | Executar `02-deploy-app.sh`; mostrar Node 26, Nginx e `systemctl status` | “O segundo script instala as dependências, publica o frontend/backend, configura o proxy e habilita os serviços.” |
| 2:20–3:35 | Abrir site no navegador; rodar cenário normal e cenário de alagamento/acidente | “A interface consulta a API Node. Os alertas e as vagas são dados simulados para demonstrar o fluxo e não representam dados em tempo real.” |
| 3:35–4:35 | `tail -f monitor.log`; mostrar métricas CPU/RAM/disco e gerar alerta com `DISK_THRESHOLD=1` | “O monitor coleta três recursos e compara os percentuais com limiares configuráveis. Os alertas são gravados em log.” |
| 4:35–5:45 | `systemctl kill --signal=SIGKILL rotaalerta.service`; aguardar e mostrar `active`/`NRestarts` | “Aqui simulamos uma falha do processo. O systemd detecta a queda e reinicia automaticamente o serviço.” |
| 5:45–6:35 | Mostrar `audit.log`, `app.log`, `journalctl` e logs Nginx | “Mantemos trilha de auditoria dos scripts, log da aplicação, monitoramento e registros do serviço.” |
| 6:35–7:00 | Tela da aplicação + terminal com serviços ativos | “Com isso, a solução está hospedada no Ubuntu e possui provisionamento automatizado, monitoramento e recuperação de falhas.” |

**Dica de gravação:** deixe a VM e o repositório preparados antes de iniciar, mas grave a execução real dos scripts e o teste de falha. Faça o teste do limiar de disco antes de gravar ou restaure o arquivo de configuração imediatamente depois. Não deixe a gravação passar de 7 minutos.

## 13. Validação técnica do pacote

Os testes já realizados durante a preparação e os testes que ainda dependem da VM final estão registrados em [`docs/VALIDACAO.md`](docs/VALIDACAO.md).

## 14. Checklist final de entrega

- [ ] Repositório contém `os/scripts/*.sh`, `os/systemd/*.service`, `os/nginx/`, `os/config/` e `os/webapp/`.
- [ ] `README.md` principal e este guia explicam como executar e testar.
- [ ] Script de infraestrutura executado sem erro.
- [ ] Script de deploy executado sem erro e health check retornou `status: ok`.
- [ ] Página acessível pelo navegador usando o IP/porta da VM.
- [ ] Cenários normal, alagamento e acidente testados.
- [ ] `rotaalerta.service`, `rotaalerta-monitor.service` e `nginx.service` ativos.
- [ ] Logs de auditoria, execução, aplicação e monitoramento gerados.
- [ ] Teste de falha comprovou reinício automático.
- [ ] Vídeo final tem até 7 minutos.
- [ ] Envio pelo Teams conforme a tarefa de Operating Systems.

---

**Importante:** execute e valide os comandos na VM do grupo antes da entrega. O script de rede em modo estático depende dos endereços reais da sua rede; use DHCP no primeiro provisionamento se não tiver certeza. A aplicação Web usa cenários simulados e não substitui nem altera o aplicativo mobile original.
