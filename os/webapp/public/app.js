'use strict';

const form = document.querySelector('#routeForm');
const button = document.querySelector('#checkButton');
const feedback = document.querySelector('#formFeedback');
const serverDot = document.querySelector('#serverDot');
const serverStatus = document.querySelector('#serverStatus');
const emptyState = document.querySelector('#emptyState');
const resultContent = document.querySelector('#resultContent');

function setServerState(online) {
  serverDot.className = `status-dot ${online ? 'online' : 'offline'}`;
  serverStatus.textContent = online ? 'Servidor online' : 'Servidor indisponível';
}

async function checkServer() {
  try {
    const response = await fetch('/api/health', { cache: 'no-store' });
    if (!response.ok) throw new Error('Health check falhou');
    setServerState(true);
  } catch {
    setServerState(false);
  }
}

function formatDate(value) {
  return new Intl.DateTimeFormat('pt-BR', { dateStyle: 'short', timeStyle: 'short' }).format(new Date(value));
}

function showResult(result) {
  emptyState.classList.add('hidden');
  resultContent.classList.remove('hidden');
  document.querySelector('#routeOrigin').textContent = result.origin;
  document.querySelector('#routeDestination').textContent = result.destination;
  document.querySelector('#statusTitle').textContent = result.statusLabel;
  document.querySelector('#statusDescription').textContent = result.incident;
  document.querySelector('#delayMetric').textContent = `${result.delayMinutes} min`;
  document.querySelector('#parkingMetric').textContent = `${result.parking.spots} vagas`;
  document.querySelector('#parkingFoot').textContent = result.parking.label;
  document.querySelector('#recommendationText').textContent = result.recommendation;
  document.querySelector('#alternativeText').textContent = result.alternative;
  document.querySelector('#checkedTime').textContent = `Verificado em ${formatDate(result.checkedAt)} · ${result.mode}`;

  const banner = document.querySelector('#statusBanner');
  const symbol = document.querySelector('#statusSymbol');
  banner.classList.toggle('warning', result.status !== 'ok');
  symbol.textContent = result.status === 'ok' ? '✓' : '!';
}

form.addEventListener('submit', async (event) => {
  event.preventDefault();
  button.disabled = true;
  button.querySelector('span:first-child').textContent = 'Analisando cenário...';
  feedback.textContent = 'Consultando o serviço local do RotaAlerta.';

  const payload = {
    routine: document.querySelector('#routine').value,
    origin: document.querySelector('#origin').value,
    destination: document.querySelector('#destination').value,
    scenario: document.querySelector('#scenario').value,
  };

  try {
    const response = await fetch('/api/route/check', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
    });
    const result = await response.json();
    if (!response.ok) throw new Error(result.error || 'Falha ao verificar rota.');
    showResult(result);
    feedback.textContent = 'Verificação concluída.';
    setServerState(true);
  } catch (error) {
    feedback.textContent = `Não foi possível concluir: ${error.message}`;
    setServerState(false);
  } finally {
    button.disabled = false;
    button.querySelector('span:first-child').textContent = 'Verificar minha rota';
  }
});

checkServer();
setInterval(checkServer, 15000);
