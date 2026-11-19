'use strict';

const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const { URL } = require('node:url');

const HOST = process.env.HOST || '127.0.0.1';
const PORT = Number.parseInt(process.env.PORT || '3000', 10);
const PUBLIC_DIR = path.join(__dirname, 'public');
const LOG_FILE = process.env.LOG_FILE || '';
const MAX_BODY_BYTES = 8 * 1024;
let lastCheck = null;

const MIME_TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.ico': 'image/x-icon',
};

function log(level, message, data = {}) {
  const line = `${new Date().toISOString()} ${level} ${message}${Object.keys(data).length ? ` ${JSON.stringify(data)}` : ''}\n`;
  process.stdout.write(line);
  if (LOG_FILE) {
    try {
      fs.appendFileSync(LOG_FILE, line, { encoding: 'utf8' });
    } catch (error) {
      process.stderr.write(`${new Date().toISOString()} ERROR Não foi possível gravar LOG_FILE: ${error.message}\n`);
    }
  }
}

function sendJson(res, statusCode, payload) {
  const body = JSON.stringify(payload);
  res.writeHead(statusCode, {
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': Buffer.byteLength(body),
    'Cache-Control': 'no-store',
  });
  res.end(body);
}

function readJson(req) {
  return new Promise((resolve, reject) => {
    let body = '';
    let size = 0;
    req.on('data', (chunk) => {
      size += chunk.length;
      if (size > MAX_BODY_BYTES) {
        reject(Object.assign(new Error('Corpo da requisição muito grande.'), { statusCode: 413 }));
        req.destroy();
        return;
      }
      body += chunk.toString('utf8');
    });
    req.on('end', () => {
      try {
        resolve(body ? JSON.parse(body) : {});
      } catch {
        reject(Object.assign(new Error('JSON inválido.'), { statusCode: 400 }));
      }
    });
    req.on('error', reject);
  });
}

function safeText(value, fallback) {
  if (typeof value !== 'string') return fallback;
  const cleaned = value.trim().replace(/[<>]/g, '').slice(0, 80);
  return cleaned.length >= 2 ? cleaned : fallback;
}

function buildScenario(scenario) {
  const common = {
    mode: 'DEMONSTRAÇÃO — DADOS SIMULADOS',
    checkedAt: new Date().toISOString(),
  };

  if (scenario === 'flood') {
    return {
      ...common,
      status: 'warning',
      statusLabel: 'Alerta de alagamento',
      delayMinutes: 25,
      incident: 'Ponto de alagamento simulado na via principal.',
      recommendation: 'Evite o trecho sinalizado e considere a rota alternativa antes de sair.',
      alternative: 'Desvio por vias locais — estimativa ilustrativa',
      parking: { available: true, spots: 3, label: 'Poucas vagas disponíveis', zone: 'Zona Azul — região de destino' },
    };
  }

  if (scenario === 'accident') {
    return {
      ...common,
      status: 'warning',
      statusLabel: 'Ocorrência na rota',
      delayMinutes: 18,
      incident: 'Colisão com lentidão simulada na avenida principal.',
      recommendation: 'Avalie sair alguns minutos antes ou utilizar o desvio sugerido.',
      alternative: 'Desvio pela avenida paralela — estimativa ilustrativa',
      parking: { available: true, spots: 6, label: 'Vagas disponíveis', zone: 'Zona Azul — região de destino' },
    };
  }

  return {
    ...common,
    status: 'ok',
    statusLabel: 'Rota sem alertas',
    delayMinutes: 0,
    incident: 'Nenhuma ocorrência simulada na rota selecionada.',
    recommendation: 'Sua rotina está dentro do cenário normal. Boa viagem!',
    alternative: 'Não é necessário desvio neste cenário.',
    parking: { available: true, spots: 8, label: 'Boa disponibilidade', zone: 'Zona Azul — região de destino' },
  };
}

async function handle(req, res) {
  const requestUrl = new URL(req.url, `http://${req.headers.host || 'localhost'}`);
  const pathname = decodeURIComponent(requestUrl.pathname);

  // Cabeçalhos básicos de segurança para a interface servida pelo próprio backend.
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('X-Frame-Options', 'DENY');
  res.setHeader('Referrer-Policy', 'strict-origin-when-cross-origin');
  res.setHeader('Content-Security-Policy', "default-src 'self'; style-src 'self'; script-src 'self'; img-src 'self' data:; connect-src 'self'; base-uri 'self'; frame-ancestors 'none'");

  if (req.method === 'GET' && pathname === '/api/health') {
    return sendJson(res, 200, {
      status: 'ok',
      service: 'rotaalerta-web',
      uptimeSeconds: Math.floor(process.uptime()),
      nodeVersion: process.version,
      timestamp: new Date().toISOString(),
    });
  }

  if (req.method === 'GET' && pathname === '/api/status') {
    return sendJson(res, 200, { status: 'ok', lastCheck, timestamp: new Date().toISOString() });
  }

  if (req.method === 'POST' && pathname === '/api/route/check') {
    try {
      const payload = await readJson(req);
      const origin = safeText(payload.origin, 'Minha casa');
      const destination = safeText(payload.destination, 'Trabalho / faculdade');
      const routine = safeText(payload.routine, 'Minha rotina');
      const scenario = ['normal', 'flood', 'accident'].includes(payload.scenario) ? payload.scenario : 'normal';
      const result = {
        routine,
        origin,
        destination,
        ...buildScenario(scenario),
      };
      lastCheck = result;
      log('INFO', 'Verificação de rota executada', {
        routine,
        scenario,
        status: result.status,
        delayMinutes: result.delayMinutes,
      });
      return sendJson(res, 200, result);
    } catch (error) {
      return sendJson(res, error.statusCode || 400, { error: error.message || 'Não foi possível verificar a rota.' });
    }
  }

  if (req.method !== 'GET' && req.method !== 'HEAD') {
    res.setHeader('Allow', 'GET, HEAD, POST');
    return sendJson(res, 405, { error: 'Método não permitido.' });
  }

  const requestedFile = pathname === '/' ? 'index.html' : pathname.replace(/^\/+/, '');
  const resolvedFile = path.resolve(PUBLIC_DIR, requestedFile);
  if (!resolvedFile.startsWith(`${PUBLIC_DIR}${path.sep}`) && resolvedFile !== path.join(PUBLIC_DIR, 'index.html')) {
    return sendJson(res, 403, { error: 'Acesso negado.' });
  }

  fs.readFile(resolvedFile, (error, contents) => {
    if (error) {
      return sendJson(res, 404, { error: 'Página ou recurso não encontrado.' });
    }
    res.writeHead(200, {
      'Content-Type': MIME_TYPES[path.extname(resolvedFile)] || 'application/octet-stream',
      'Content-Length': contents.length,
      'Cache-Control': path.extname(resolvedFile) === '.html' ? 'no-cache' : 'public, max-age=3600',
    });
    return res.end(req.method === 'HEAD' ? undefined : contents);
  });
}

const server = http.createServer((req, res) => {
  handle(req, res).catch((error) => {
    log('ERROR', 'Falha não tratada ao processar requisição', { message: error.message });
    if (!res.headersSent) sendJson(res, 500, { error: 'Erro interno do servidor.' });
    else res.destroy();
  });
});

server.listen(PORT, HOST, () => {
  log('INFO', 'Servidor RotaAlerta iniciado', { host: HOST, port: PORT, node: process.version });
});

function shutdown(signal) {
  log('INFO', 'Encerramento solicitado', { signal });
  server.close(() => {
    log('INFO', 'Servidor encerrado com segurança');
    process.exit(0);
  });
  setTimeout(() => process.exit(1), 10000).unref();
}

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));
process.on('uncaughtException', (error) => {
  log('ERROR', 'uncaughtException', { message: error.message, stack: error.stack });
  process.exit(1);
});
process.on('unhandledRejection', (reason) => {
  log('ERROR', 'unhandledRejection', { reason: String(reason) });
  process.exit(1);
});
