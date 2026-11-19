# RotaAlerta

App de GPS que **avisa antes de você sair de casa** se há problemas na sua rota de rotina (acidente, obra, metrô parado…), mostrando o atraso, o novo horário de chegada e uma rota alternativa.  
Projeto acadêmico interdisciplinar (**Global Solution**), contemplando o aplicativo mobile em **React Native + TypeScript + Expo + Expo Router** e a **infraestrutura Linux automatizada em Ubuntu Server** (Seção 11).

> **Entrega de Operating Systems (Infraestrutura Linux & Web):**  
> Acesse diretamente a [Seção 11](#11-operating-systems--infraestrutura-ubuntu-e-versão-web), a documentação técnica em [`os/README.md`](os/README.md), o relatório de testes em [`os/docs/VALIDACAO.md`](os/docs/VALIDACAO.md) e os logs/evidências em [`os/evidencias/`](os/evidencias/).

- **Autores:**
  1. Bruno Otavio Silva De Oliveira — RM556196
  2. Guilherme Flores Pereira de Almeida — RM554948
  3. Leonardo Gonçalves Novaes — RM554807
  4. Luiz Fernando de Aragão Souza — RM555561
  5. Marcello de Freitas Moreira — RM557531

---

## Problema e proposta

Perder tempo no trânsito é um problema diário de estudantes e trabalhadores. Google Maps e Waze mostram o melhor trajeto, mas o usuário normalmente só descobre o problema **quando já está no meio dele**.

**Proposta:** o usuário cadastra suas rotas de rotina (ex.: casa → trabalho, saída às 06:00). O app verifica essas rotas e avisa **antes da saída**, por exemplo:

> Acidente de carros (Av. dos Estados): atraso médio de 30 min (chegada às 08:30). Rota alternativa pela Av. Y: tempo total de 2 h 10 min (chegada às 08:10).

**Público-alvo:** jovens adultos, estudantes e trabalhadores que fazem o mesmo trajeto de carro todos os dias.


---

##  Operating Systems — infraestrutura Ubuntu e versão Web

-- video:(https://youtu.be/6kuaXnsU7og)

A implementação de **Operating Systems** da Global Solution está na pasta [`os/`](os/README.md). Ela adiciona uma aplicação Web CitizenTech complementar (`os/webapp/`) e uma suíte completa de scripts Bash para provisionamento de infraestrutura, deploy automatizado, monitoramento contínuo de CPU/memória/disco com alertas, trilha de auditoria, serviços `systemd` tolerantes a falhas e testes automatizados de recuperação.

- **Documentação técnica completa:** [`os/README.md`](os/README.md)
- **Relatório de validação executado na VM:** [`os/docs/VALIDACAO.md`](os/docs/VALIDACAO.md)
- **Roteiro do vídeo de demonstração (até 7 min):** [`os/docs/roteiro-video.md`](os/docs/roteiro-video.md)
- **Evidências técnicas, logs reais e relatórios de falha:** [`os/evidencias/`](os/evidencias/)

### Atendimento aos Critérios de Operating Systems

| Critério | Peso | Implementação |
|---|---|---|
| **Provisionamento de infra** (Rede, DNS, IP, Hostname) | 2,0 pts | [`os/scripts/01-provision-infra.sh`](os/scripts/01-provision-infra.sh) — Configura hostname (`rotaalerta-server`), `/etc/hosts`, DNS persistente via `systemd-resolved`, rede via Netplan (DHCP ou estático) e firewall `ufw`. |
| **Provisionamento da aplicação** | 2,0 pts | [`os/scripts/02-deploy-app.sh`](os/scripts/02-deploy-app.sh) — Instala Node.js 26 LTS e Nginx, cria usuário dedicado `rotaalerta`, configura `/etc/rotaalerta/rotaalerta.env`, ativa o proxy reverso HTTP e valida `/api/health`. |
| **Monitoramento com alertas** (CPU, Disco e Memória) | 2,0 pts | [`os/scripts/03-monitor.sh`](os/scripts/03-monitor.sh) — Coleta métricas reais (`/proc/stat`, `/proc/meminfo`, `df`) e registra `[ALERTA]` em `/var/log/rotaalerta/monitor.log` e no `journald` (`logger`). |
| **Monitoramento como serviço tolerante a falhas** | 1,0 pt | [`os/systemd/rotaalerta.service`](os/systemd/rotaalerta.service) e [`os/systemd/rotaalerta-monitor.service`](os/systemd/rotaalerta-monitor.service) configurados com `Restart=always` e `StartLimitIntervalSec=0`. |
| **Logs de auditoria e execução** | 1,0 pt | [`os/scripts/common.sh`](os/scripts/common.sh) gera `/var/log/rotaalerta/audit.log` (ator, script e evento) e logs individuais por script com rotação diária via [`os/logrotate/rotaalerta`](os/logrotate/rotaalerta). |
| **Teste de falha e funcionamento completo** | 2,0 pts | [`os/scripts/04-failure-test.sh`](os/scripts/04-failure-test.sh) injeta `SIGKILL` nos serviços para comprovar reinício automático pelo `systemd` e gera carga real de CPU, disco e RAM, salvando evidências em [`os/evidencias/`](os/evidencias/). |

### Execução rápida na VM Ubuntu Server

```bash
# 1. Provisionar rede, DNS, hostname e firewall
sudo bash os/scripts/01-provision-infra.sh

# 2. Instalar Node.js/Nginx, publicar a aplicação e subir os serviços systemd
sudo bash os/scripts/02-deploy-app.sh

# 3. Executar testes automatizados de queda (SIGKILL) e carga de recursos
sudo bash os/scripts/04-failure-test.sh
```
