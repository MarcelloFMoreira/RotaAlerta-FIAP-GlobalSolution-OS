# Validação Técnica do Ambiente


**Data da validação:** 19/11/2026
**Sistema Operacional:** Ubuntu 26.04.1 LTS (Kernel Linux 7.0.0-43-generic, VirtualBox)
**Stack instalada:** Node.js v26.13.1, npm 11.20.0, Nginx 1.28.3
**Hostname e Rede:** rotaalerta-server, interface enp0s3 ativa, DNS persistente via systemd-resolved (1.1.1.1 / 8.8.8.8)
## Resultados dos Testes Automatizados (04-failure-test.sh)


1. **Recuperação da Aplicação (SIGKILL):** PASSOU — systemd reiniciou o serviço automaticamente em **7s** (novo PID atribuído e /api/health restabelecido).
2. **Recuperação do Monitor (SIGKILL):** PASSOU — systemd reiniciou o serviço automaticamente em **10s** e a gravação em /var/log/rotaalerta/monitor.log foi retomada.
3. **Alertas de Recursos (CPU, RAM e Disco):** PASSOU — Disparos [ALERTA] registrados em /var/log/rotaalerta/monitor.log e no journald ao ultrapassar os limites configurados (CPU=100.0%, DISCO_ROOT=88%, RAM=35.1% sobre limiar ajustado de 30%), mantendo /api/health ativo durante toda a carga.
4. **Auditoria e Rotação de Logs:** PASSOU — /var/log/rotaalerta/audit.log registra ator, script e evento; logrotate validado sem erros de permissão.


Evidências completas disponíveis em [os/evidencias/](../evidencias/).
