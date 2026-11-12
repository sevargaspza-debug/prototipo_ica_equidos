// ============================================================================
// Servicio local del prototipo ICA — API de sincronización con MariaDB
// - Expone /api/state, /api/health y /api/resumen.
// - Guarda el estado JSON y lo proyecta sobre el modelo relacional V3.
// - También sirve la SPA en desarrollo (http://127.0.0.1:3001).
// - En Docker, Nginx sirve la SPA y redirige /api a este proceso.
// ============================================================================

const http = require('http');
const fs = require('fs');
const path = require('path');
const mysql = require('mysql2/promise');

const { ensureSchema, syncState } = require('./sync-service');

/* ----------------------------- Configuración ----------------------------- */

function cargarEnvLocal() {
  const ruta = path.resolve(__dirname, '..', '.env');
  if (!fs.existsSync(ruta)) return;
  const texto = fs.readFileSync(ruta, 'utf8');
  for (const linea of texto.split(/\r?\n/)) {
    const limpia = linea.trim();
    if (!limpia || limpia.startsWith('#')) continue;
    const pos = limpia.indexOf('=');
    if (pos < 0) continue;
    const clave = limpia.slice(0, pos).trim();
    let valor = limpia.slice(pos + 1).trim();
    if ((valor.startsWith('"') && valor.endsWith('"'))
      || (valor.startsWith("'") && valor.endsWith("'"))) {
      valor = valor.slice(1, -1);
    }
    if (!(clave in process.env)) process.env[clave] = valor;
  }
}

cargarEnvLocal();

const PUERTO = Number(process.env.DB_API_PORT || 3001);
const HOST = process.env.DB_API_HOST || '127.0.0.1';
const RAIZ = path.resolve(__dirname, '..');
const MAX_CUERPO_BYTES = 10 * 1024 * 1024;

const pool = mysql.createPool({
  host: process.env.DB_HOST || '127.0.0.1',
  port: Number(process.env.DB_PORT || 3307),
  user: process.env.DB_USER || 'ica_app',
  password: process.env.DB_PASSWORD || '',
  database: process.env.DB_NAME || 'ica_equidos',
  charset: 'utf8mb4_unicode_ci',
  waitForConnections: true,
  connectionLimit: 10,
  queueLimit: 0,
  timezone: 'Z',
  dateStrings: true
});

let esquemaListo = false;

/* ------------------------------- Utilidades ------------------------------ */

function cabecerasCors() {
  return {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type',
    'Access-Control-Allow-Private-Network': 'true',
    'Access-Control-Max-Age': '86400'
  };
}

function responderJson(res, status, cuerpo) {
  const texto = JSON.stringify(cuerpo);
  res.writeHead(status, Object.assign({
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': Buffer.byteLength(texto),
    'Cache-Control': 'no-store'
  }, cabecerasCors()));
  res.end(texto);
}

function leerCuerpo(req) {
  return new Promise((resolve, reject) => {
    const partes = [];
    let total = 0;
    let excedido = false;

    req.on('data', (trozo) => {
      if (excedido) return;
      total += trozo.length;
      if (total > MAX_CUERPO_BYTES) {
        excedido = true;
        reject(Object.assign(new Error('El cuerpo de la petición es demasiado grande.'), { status: 413 }));
        return;
      }
      partes.push(trozo);
    });
    req.on('end', () => {
      if (!excedido) resolve(Buffer.concat(partes).toString('utf8'));
    });
    req.on('error', reject);
  });
}

function usuarioDe(valor) {
  return String(valor || '').trim().slice(0, 150);
}

async function asegurarEsquema() {
  if (esquemaListo) return;
  await ensureSchema(pool);
  esquemaListo = true;
}

/* --------------------------------- API ----------------------------------- */

async function manejarApi(req, res, url) {
  if (req.method === 'OPTIONS') {
    res.writeHead(204, cabecerasCors());
    res.end();
    return;
  }

  if (url.pathname === '/api/health' && req.method === 'GET') {
    try {
      const [filas] = await pool.query(
        'SELECT VERSION() AS version, @@port AS puerto, DATABASE() AS base_datos'
      );
      const [tablas] = await pool.query(
        `SELECT COUNT(*) AS total
         FROM information_schema.tables
         WHERE table_schema = DATABASE() AND table_type = 'BASE TABLE'`
      );
      responderJson(res, 200, {
        ok: true,
        ...filas[0],
        tablas: tablas[0].total,
        hora: new Date().toISOString()
      });
    } catch (error) {
      responderJson(res, 503, { ok: false, error: error.message });
    }
    return;
  }

  if (url.pathname === '/api/state' && req.method === 'GET') {
    const usuario = usuarioDe(url.searchParams.get('usuario') || 'principal');
    try {
      const [filas] = await pool.execute(
        `SELECT estado_json, version, actualizado_en
         FROM estado_aplicacion
         WHERE usuario = ?`,
        [usuario]
      );

      if (filas.length === 0) {
        responderJson(res, 200, {
          ok: true,
          usuario,
          state: null,
          version: 0,
          actualizado_en: null
        });
        return;
      }

      const fila = filas[0];
      const state = typeof fila.estado_json === 'string'
        ? JSON.parse(fila.estado_json)
        : fila.estado_json;

      responderJson(res, 200, {
        ok: true,
        usuario,
        state,
        version: fila.version,
        actualizado_en: fila.actualizado_en
      });
    } catch (error) {
      responderJson(res, 500, { ok: false, error: error.message });
    }
    return;
  }

  if (url.pathname === '/api/state' && req.method === 'POST') {
    try {
      const crudo = await leerCuerpo(req);
      let cuerpo;
      try { cuerpo = JSON.parse(crudo); }
      catch (e) {
        responderJson(res, 400, { ok: false, error: 'El cuerpo debe ser JSON válido.' });
        return;
      }

      const usuario = usuarioDe(cuerpo && cuerpo.usuario);
      const state = cuerpo ? cuerpo.state : null;

      if (!usuario) {
        responderJson(res, 400, { ok: false, error: 'Falta el usuario.' });
        return;
      }
      if (!state || typeof state !== 'object' || Array.isArray(state)) {
        responderJson(res, 400, { ok: false, error: 'El estado debe ser un objeto JSON.' });
        return;
      }

      await asegurarEsquema();
      const resultado = await syncState(pool, usuario, state);
      console.log(
        `[sync] usuario=${usuario} fincas=${resultado.fincas} evaluaciones=${resultado.evaluaciones} respuestas=${resultado.respuestas}`
      );
      responderJson(res, 200, { ok: true, usuario, ...resultado });
    } catch (error) {
      const status = error && error.status ? error.status : 500;
      responderJson(res, status, {
        ok: false,
        error: error && error.sqlMessage ? error.sqlMessage : error.message
      });
    }
    return;
  }

  if (url.pathname === '/api/resumen' && req.method === 'GET') {
    try {
      const [conteos] = await pool.query(`
        SELECT
          (SELECT COUNT(*) FROM fincas) AS fincas,
          (SELECT COUNT(*) FROM inventario_equino WHERE activo = TRUE) AS inventario,
          (SELECT COUNT(*) FROM evaluaciones) AS evaluaciones,
          (SELECT COUNT(*) FROM detalle_respuestas) AS respuestas,
          (SELECT COUNT(*) FROM resultado_libertad) AS resultados,
          (SELECT COUNT(*) FROM documento_soporte) AS documentos,
          (SELECT COUNT(*) FROM plan_mejora) AS planes,
          (SELECT COUNT(*) FROM estado_aplicacion) AS estados
      `);
      const [evaluaciones] = await pool.query(`
        SELECT *
        FROM vw_resumen_evaluacion
        ORDER BY fecha_evaluacion DESC
        LIMIT 20
      `);
      responderJson(res, 200, { ok: true, conteos: conteos[0], evaluaciones });
    } catch (error) {
      responderJson(res, 500, { ok: false, error: error.message });
    }
    return;
  }

  responderJson(res, 404, { ok: false, error: 'Ruta de API no encontrada.' });
}

/* ------------------------------- Estáticos ------------------------------- */

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.gif': 'image/gif',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
  '.ttf': 'font/ttf',
  '.pdf': 'application/pdf'
};

const BLOQUEADOS = [
  '/.git',
  '/.env',
  '/.dockerignore',
  '/.gitignore',
  '/node_modules',
  '/server',
  '/db',
  '/docker',
  '/nginx',
  '/api',
  '/package.json',
  '/package-lock.json'
];

function estaBloqueado(rel) {
  return BLOQUEADOS.some(prefijo => rel === prefijo || rel.startsWith(prefijo + '/'));
}

function servirEstatico(req, res, url) {
  if (req.method !== 'GET' && req.method !== 'HEAD') {
    responderJson(res, 405, { ok: false, error: 'Método no permitido.' });
    return;
  }

  let rel;
  try {
    rel = decodeURIComponent(url.pathname);
  } catch (error) {
    responderJson(res, 400, { ok: false, error: 'Ruta inválida.' });
    return;
  }

  if (rel === '/' || rel === '') rel = '/index.html';
  if (estaBloqueado(rel)) {
    responderJson(res, 404, { ok: false, error: 'Recurso no encontrado.' });
    return;
  }

  let archivo = path.resolve(RAIZ, '.' + rel);
  if (archivo !== RAIZ && !archivo.startsWith(RAIZ + path.sep)) {
    responderJson(res, 403, { ok: false, error: 'Acceso denegado.' });
    return;
  }

  if (!fs.existsSync(archivo) || !fs.statSync(archivo).isFile()) {
    if (path.extname(rel)) {
      responderJson(res, 404, { ok: false, error: 'Recurso no encontrado.' });
      return;
    }
    archivo = path.join(RAIZ, 'index.html');
  }

  const extension = path.extname(archivo).toLowerCase();
  const stats = fs.statSync(archivo);
  res.writeHead(200, {
    'Content-Type': MIME[extension] || 'application/octet-stream',
    'Content-Length': stats.size,
    'Cache-Control': 'no-cache'
  });

  if (req.method === 'HEAD') {
    res.end();
    return;
  }
  fs.createReadStream(archivo).pipe(res);
}

/* -------------------------------- Servidor ------------------------------- */

const servidor = http.createServer((req, res) => {
  let url;
  try {
    url = new URL(req.url, `http://${req.headers.host || 'localhost'}`);
  } catch (error) {
    responderJson(res, 400, { ok: false, error: 'URL inválida.' });
    return;
  }

  if (url.pathname === '/api' || url.pathname.startsWith('/api/')) {
    manejarApi(req, res, url).catch(error => {
      console.error('[api]', error);
      if (!res.headersSent) {
        responderJson(res, 500, { ok: false, error: error.message });
      }
    });
    return;
  }

  servirEstatico(req, res, url);
});

servidor.listen(PUERTO, HOST, () => {
  console.log('');
  console.log('============================================================');
  console.log('  Sistema ICA de Bienestar Animal en Équidos');
  console.log(`  Interfaz:  http://${HOST}:${PUERTO}`);
  console.log(`  API:       http://${HOST}:${PUERTO}/api/health`);
  console.log(`  MariaDB:   ${process.env.DB_HOST || '127.0.0.1'}:${process.env.DB_PORT || 3307} · ${process.env.DB_NAME || 'ica_equidos'}`);
  console.log('  Sincronización activa: localStorage ↔ MariaDB');
  console.log('============================================================');
  console.log('');

  asegurarEsquema()
    .then(() => console.log('[db] esquema verificado'))
    .catch(error => {
      console.error('[db] no se pudo verificar el esquema:', error.message);
      console.error('[db] importe Script_BD_ICA_Equidos_V3_MariaDB_Sync.sql o revise las credenciales.');
    });
});

async function detener(senal) {
  console.log(`\n${senal}: cerrando servidor...`);
  servidor.close(async () => {
    await pool.end().catch(() => {});
    process.exit(0);
  });
}

process.on('SIGINT', () => detener('SIGINT'));
process.on('SIGTERM', () => detener('SIGTERM'));
