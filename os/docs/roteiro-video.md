# Roteiro de gravação — Operating Systems (até 7 minutos)

| Tempo | Tela/ação | Narração sugerida |
|---|---|---|
| 0:00–0:25 | Apresentar RotaAlerta | O RotaAlerta ajuda estudantes e trabalhadores a antecipar imprevistos da rota habitual, reduzindo surpresas no deslocamento. |
| 0:25–1:25 | Rodar `01-provision-infra.sh`; exibir `hostnamectl`, `ip -br address`, `ip route` e `resolvectl status` | O primeiro script prepara o Ubuntu, configura hostname, identifica interface de rede, mantém DHCP ou aplica IP estático e configura DNS persistente. |
| 1:25–2:20 | Rodar `02-deploy-app.sh`; exibir `node --version`, `systemctl status` | O segundo script instala Node.js e Nginx, publica a aplicação, cria os serviços e valida a API. |
| 2:20–3:35 | Navegador: cenário normal, alagamento e acidente | A aplicação consulta o backend Node.js e apresenta alertas e vagas simulados para demonstrar a proposta. |
| 3:35–4:35 | Exibir `monitor.log`; reduzir temporariamente `DISK_THRESHOLD` para 1 | O monitor acompanha CPU, memória e disco, registra as métricas e cria alertas quando um limite é atingido. |
| 4:35–5:45 | Matar o serviço com SIGKILL e mostrar o retorno | O systemd identifica a falha e reinicia automaticamente o processo, mantendo a aplicação disponível após a recuperação. |
| 5:45–6:35 | Exibir `audit.log`, `app.log` e `journalctl` | A execução fica documentada em logs de auditoria, aplicação, monitoramento e serviços. |
| 6:35–7:00 | Mostrar site e serviços ativos | A solução está hospedada no Ubuntu e conta com provisionamento automatizado, monitoramento e recuperação de falhas. |

## Comandos para deixar preparados

```bash
sudo bash os/scripts/01-provision-infra.sh
sudo bash os/scripts/02-deploy-app.sh
hostname -I
sudo systemctl status rotaalerta rotaalerta-monitor nginx
```

Teste de monitoramento controlado:

```bash
sudo cp /etc/rotaalerta/rotaalerta.env /etc/rotaalerta/rotaalerta.env.bak
sudo sed -i 's/^DISK_THRESHOLD=.*/DISK_THRESHOLD=1/' /etc/rotaalerta/rotaalerta.env
sudo systemctl restart rotaalerta-monitor
sleep 5
sudo tail -n 12 /var/log/rotaalerta/monitor.log
sudo mv /etc/rotaalerta/rotaalerta.env.bak /etc/rotaalerta/rotaalerta.env
sudo systemctl restart rotaalerta-monitor
```

Teste de recuperação:

```bash
sudo systemctl show rotaalerta -p ActiveState -p NRestarts
sudo systemctl kill --signal=SIGKILL rotaalerta
sleep 7
sudo systemctl status rotaalerta
sudo systemctl show rotaalerta -p ActiveState -p NRestarts
curl -I http://127.0.0.1/
```
