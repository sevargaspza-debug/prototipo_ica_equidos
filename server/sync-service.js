// ============================================================================
// Sincronización prototipo ICA ↔ MariaDB
// - Guarda el estado completo del prototipo en estado_aplicacion.
// - Proyecta el estado sobre las tablas normalizadas del modelo V3.
// - Usa IDs deterministas para que las sincronizaciones sean idempotentes.
// ============================================================================

const crypto = require('crypto');

const LIBERTADES = [
  { id: 'L1', numero: 1, peso: 20 },
  { id: 'L2', numero: 2, peso: 15 },
  { id: 'L3', numero: 3, peso: 30 },
  { id: 'L4', numero: 4, peso: 15 },
  { id: 'L5', numero: 5, peso: 20 }
];

const TIPO_FINCA = {
  criadero: 'criadero',
  deporte: 'deporte',
  traspatio: 'traspatio',
  trabajo: 'trabajo',
  exhibicion: 'deporte',   // el modelo V3 solo admite cuatro tipos
  produccion: 'criadero'   // se conserva el valor original en observaciones
};

const SISTEMA_PRODUCTIVO = {
  pesebrera: 'pesebrera',
  potrero: 'potrero',
  mixto: 'mixto'
};

const ESTADO_EVALUACION = {
  EN_PROCESO: 'en_proceso',
  SUSPENDIDA: 'suspendida',
  FINALIZADA: 'finalizada'
};

const CATEGORIA_ETARIA = {
  cria: 'CRIA_LACTANTE',
  joven: 'JOVEN',
  adulto: 'ADULTO',
  geronte: 'GERONTE'
};

const ESPECIES = new Set(['caballar', 'asnal', 'mular', 'burdegano', 'cebroide']);
const SEXOS = new Set(['macho', 'hembra', 'indeterminado']);
const PUNTAJES = new Set([0, 20, 55, 100]);

/* ------------------------------ Utilidades ------------------------------- */

function hash32(text, seed = 0) {
  let h = (2166136261 ^ seed) >>> 0;
  for (let i = 0; i < text.length; i += 1) {
    h ^= text.charCodeAt(i);
    h = Math.imul(h, 16777619);
  }
  return h >>> 0;
}

/**
 * UUID determinista (formato UUID v4) a partir de un namespace y un valor.
 * Así, el mismo registro del prototipo siempre obtiene la misma PK en MariaDB.
 */
function uuidFrom(namespace, value) {
  const s = String(value);
  const a = hash32(`${namespace}:${s}:a`, 0x9e3779b9).toString(16).padStart(8, '0');
  const b = hash32(`${namespace}:${s}:b`, 0x85ebca6b).toString(16).padStart(4, '0').slice(0, 4);
  const c = '4' + hash32(`${namespace}:${s}:c`, 0xc2b2ae35).toString(16).padStart(3, '0').slice(0, 3);
  const d = ((((hash32(`${namespace}:${s}:d`, 0x27d4eb2f) >>> 28) & 0x3) | 0x8).toString(16))
    + hash32(`${namespace}:${s}:e`, 0x165667b1).toString(16).padStart(3, '0').slice(0, 3);
  const e = (
    hash32(`${namespace}:${s}:f`, 0x1b873593).toString(16).padStart(8, '0')
    + hash32(`${namespace}:${s}:g`, 0xcc9e2d51).toString(16).padStart(4, '0')
  ).slice(0, 12);
  return `${a}-${b}-${c}-${d}-${e}`;
}

function toDateOnly(value) {
  if (!value) return new Date().toISOString().slice(0, 10);
  const d = new Date(value);
  if (Number.isNaN(d.getTime())) return String(value).slice(0, 10);
  return d.toISOString().slice(0, 10);
}

function toDateTime(value) {
  if (!value) return null;
  const d = new Date(value);
  if (Number.isNaN(d.getTime())) return null;
  return d.toISOString().slice(0, 19).replace('T', ' ');
}

function truncate(text, max) {
  const s = String(text || '');
  return s.length <= max ? s : s.slice(0, max);
}

function round2(value) {
  return Math.round((Number(value) + Number.EPSILON) * 100) / 100;
}

function safeNumber(value, fallback = 0) {
  const n = Number(value);
  return Number.isFinite(n) ? n : fallback;
}

function normalizeDate(value, fallbackDays = 30) {
  if (value) return toDateOnly(value);
  return toDateOnly(new Date(Date.now() + fallbackDays * 86400000));
}

/* ------------------------- Resultados por libertad ----------------------- */

function resultadosNormalizados(ev, indMap) {
  const desdeEstado = ev && ev.resultados && Array.isArray(ev.resultados.porLibertad)
    ? ev.resultados.porLibertad
    : null;

  if (desdeEstado) {
    return LIBERTADES.map(lib => {
      const item = desdeEstado.find(x => x.libertadId === lib.id) || {};
      const promedio = safeNumber(item.promedio);
      const ponderado = safeNumber(item.ponderado) * 100;
      return {
        libertadId: lib.id,
        numero: lib.numero,
        promedio: round2(promedio),
        ponderado: round2(ponderado),
        cumplido: promedio >= 75
      };
    });
  }

  const respuestas = ev && ev.respuestas ? ev.respuestas : {};
  return LIBERTADES.map(lib => {
    const items = Object.entries(respuestas).filter(([codigo, r]) => {
      const ind = indMap.get(codigo);
      return ind
        && Number(ind.id_libertad) === lib.numero
        && r
        && r.score !== null
        && r.score !== undefined;
    });
    const n = items.length;
    const suma = items.reduce((acc, [, r]) => acc + safeNumber(r.score), 0);
    const promedio = n > 0 ? suma / n : 0;
    const ponderado = (promedio / 100) * lib.peso;
    return {
      libertadId: lib.id,
      numero: lib.numero,
      promedio: round2(promedio),
      ponderado: round2(ponderado),
      cumplido: promedio >= 75
    };
  });
}

/* ------------------------------- Esquema --------------------------------- */

async function ensureSchema(pool) {
  const [rows] = await pool.query(
    `SELECT COUNT(*) AS total
     FROM information_schema.tables
     WHERE table_schema = DATABASE() AND table_name = 'estado_aplicacion'`
  );
  if (Number(rows[0].total) > 0) return;

  await pool.query(`
    CREATE TABLE IF NOT EXISTS estado_aplicacion (
      usuario VARCHAR(150) NOT NULL,
      estado_json JSON NOT NULL,
      version INT UNSIGNED NOT NULL DEFAULT 1,
      actualizado_en TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
        ON UPDATE CURRENT_TIMESTAMP,
      PRIMARY KEY (usuario)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
      COMMENT='Respaldo JSON del estado del prototipo para sincronización'
  `);
}

/* ------------------------- Sincronización principal ---------------------- */

async function syncState(pool, usuario, state) {
  const conn = await pool.getConnection();
  try {
    await conn.beginTransaction();

    await conn.execute(
      `INSERT INTO estado_aplicacion (usuario, estado_json, version)
       VALUES (?, ?, 1)
       ON DUPLICATE KEY UPDATE
         estado_json = VALUES(estado_json),
         version = version + 1`,
      [usuario, JSON.stringify(state)]
    );

    const [indRows] = await conn.query(
      'SELECT codigo, id_indicador, id_libertad, descripcion FROM indicadores_checklist'
    );
    const indMap = new Map(indRows.map(r => [r.codigo, r]));

    const [catRows] = await conn.query(
      'SELECT codigo, id_categoria FROM catalogo_categoria_etaria'
    );
    const catMap = new Map(catRows.map(r => [r.codigo, r.id_categoria]));

    const [docRows] = await conn.query(
      'SELECT codigo, nombre FROM catalogo_documento'
    );
    const docMap = new Map(docRows.map(r => [r.codigo, r]));

    const resumen = {
      fincas: 0,
      inventario: 0,
      evaluaciones: 0,
      respuestas: 0,
      resultados: 0,
      documentos: 0,
      planes: 0
    };

    const fincas = Array.isArray(state.fincas) ? state.fincas : [];
    const inventario = Array.isArray(state.inventario) ? state.inventario : [];
    const evaluaciones = Array.isArray(state.evaluaciones) ? state.evaluaciones : [];
    const fincaUuid = new Map();

    /* ----------------------------- Fincas ------------------------------- */
    for (const finca of fincas) {
      const idFinca = uuidFrom('finca', finca.id);
      fincaUuid.set(String(finca.id), idFinca);

      const tipo = TIPO_FINCA[finca.tipo] || 'criadero';
      const sistema = SISTEMA_PRODUCTIVO[finca.sistema] || 'mixto';
      const msnm = Math.max(0, safeNumber(finca.msnm));
      const observaciones = JSON.stringify({
        vereda: finca.vereda || null,
        lat: finca.lat || null,
        lon: finca.lon || null,
        creada: finca.creada || null,
        tipo_original: finca.tipo || null,
        sistema_original: finca.sistema || null
      });

      await conn.execute(
        `INSERT INTO fincas
           (id_finca, nombre_finca, propietario, direccion, municipio,
            departamento, msnm, tipo, sistema_productivo, observaciones, activo)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, TRUE)
         ON DUPLICATE KEY UPDATE
           nombre_finca = VALUES(nombre_finca),
           propietario = VALUES(propietario),
           direccion = VALUES(direccion),
           municipio = VALUES(municipio),
           departamento = VALUES(departamento),
           msnm = VALUES(msnm),
           tipo = VALUES(tipo),
           sistema_productivo = VALUES(sistema_productivo),
           observaciones = VALUES(observaciones),
           activo = TRUE`,
        [
          idFinca,
          truncate(finca.nombre || 'Finca sin nombre', 255),
          truncate(finca.propietario || 'Sin propietario', 255),
          truncate(finca.vereda || 'No registrada', 500),
          truncate(finca.municipio || 'No registrado', 150),
          truncate(finca.departamento || 'No registrado', 150),
          msnm,
          tipo,
          sistema,
          observaciones
        ]
      );
      resumen.fincas += 1;

      /* --------------------------- Inventario --------------------------- */
      const filasInventario = inventario.filter(
        i => String(i.fincaId) === String(finca.id)
      );
      const idsInventario = [];

      for (const item of filasInventario) {
        const idEquino = uuidFrom(
          'inventario',
          item.id !== undefined && item.id !== null
            ? item.id
            : `${finca.id}:${item.especie}:${item.edad}:${item.sexo}:${item.identificacion || ''}`
        );
        idsInventario.push(idEquino);

        const especie = ESPECIES.has(item.especie) ? item.especie : 'caballar';
        const sexo = SEXOS.has(item.sexo) ? item.sexo : 'indeterminado';
        const codigoCategoria = CATEGORIA_ETARIA[item.edad] || null;
        const idCategoria = codigoCategoria ? (catMap.get(codigoCategoria) || null) : null;

        await conn.execute(
          `INSERT INTO inventario_equino
             (id_equino, id_finca, id_categoria_etaria, especie, sexo, cantidad,
              nombre_identificacion, categoria_etaria, observaciones, activo)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, TRUE)
           ON DUPLICATE KEY UPDATE
             id_finca = VALUES(id_finca),
             id_categoria_etaria = VALUES(id_categoria_etaria),
             especie = VALUES(especie),
             sexo = VALUES(sexo),
             cantidad = VALUES(cantidad),
             nombre_identificacion = VALUES(nombre_identificacion),
             categoria_etaria = VALUES(categoria_etaria),
             observaciones = VALUES(observaciones),
             activo = TRUE`,
          [
            idEquino,
            idFinca,
            idCategoria,
            especie,
            sexo,
            Math.max(1, Math.trunc(safeNumber(item.cantidad, 1))),
            truncate(item.identificacion || '', 100) || null,
            truncate(item.edad || '', 100) || null,
            item.ubicacion || null
          ]
        );
        resumen.inventario += 1;
      }

      if (idsInventario.length > 0) {
        const placeholders = idsInventario.map(() => '?').join(',');
        await conn.query(
          `DELETE FROM inventario_equino
           WHERE id_finca = ? AND id_equino NOT IN (${placeholders})`,
          [idFinca, ...idsInventario]
        );
      } else {
        await conn.execute(
          'DELETE FROM inventario_equino WHERE id_finca = ?',
          [idFinca]
        );
      }
    }

    /* --------------------------- Evaluaciones --------------------------- */
    for (const ev of evaluaciones) {
      const idFinca = fincaUuid.get(String(ev.fincaId));
      if (!idFinca) continue;

      const finca = fincas.find(f => String(f.id) === String(ev.fincaId)) || {};
      const idEvaluacion = uuidFrom('evaluacion', ev.id);
      const muestra = ev.muestra || {};
      const total = Math.max(0, Math.trunc(safeNumber(muestra.total)));
      const ajustada = Math.max(
        0,
        Math.min(total || 0, Math.trunc(safeNumber(muestra.ajustada, total)))
      );
      const porcentaje = total > 0 ? round2((ajustada / total) * 100) : null;
      const estado = ESTADO_EVALUACION[ev.estado] || 'en_proceso';
      const motivo = estado === 'suspendida'
        ? (ev.suspension && ev.suspension.motivo ? ev.suspension.motivo : 'Suspensión registrada en el prototipo')
        : null;
      const clasificacion = ev.resultados && ev.resultados.clasificacion
        ? ev.resultados.clasificacion
        : null;
      const respuestas = ev.respuestas || {};
      const requierePlan = Object.keys(ev.plan || {}).length > 0
        || Object.values(respuestas).some(r => r && (r.trat || (r.score !== null && r.score !== undefined && Number(r.score) < 100)));

      await conn.execute(
        `INSERT INTO evaluaciones
           (id_evaluacion, id_finca, codigo_evaluacion, fecha_evaluacion,
            hora_inicio, hora_fin, evaluador_principal, capitulo,
            tipo_finca_aplicado, sistema_productivo_aplicado, msnm_evaluacion,
            total_animales, muestra_calculada, muestra_ajustada,
            justificacion_muestra, porcentaje_total, clasificacion, estado,
            etapa_actual, motivo_suspension, fecha_suspension,
            requiere_plan_mejora, creado_por, finalizado_en)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
         ON DUPLICATE KEY UPDATE
           id_finca = VALUES(id_finca),
           codigo_evaluacion = VALUES(codigo_evaluacion),
           fecha_evaluacion = VALUES(fecha_evaluacion),
           hora_inicio = VALUES(hora_inicio),
           hora_fin = VALUES(hora_fin),
           evaluador_principal = VALUES(evaluador_principal),
           capitulo = VALUES(capitulo),
           tipo_finca_aplicado = VALUES(tipo_finca_aplicado),
           sistema_productivo_aplicado = VALUES(sistema_productivo_aplicado),
           msnm_evaluacion = VALUES(msnm_evaluacion),
           total_animales = VALUES(total_animales),
           muestra_calculada = VALUES(muestra_calculada),
           muestra_ajustada = VALUES(muestra_ajustada),
           justificacion_muestra = VALUES(justificacion_muestra),
           porcentaje_total = VALUES(porcentaje_total),
           clasificacion = VALUES(clasificacion),
           estado = VALUES(estado),
           etapa_actual = VALUES(etapa_actual),
           motivo_suspension = VALUES(motivo_suspension),
           fecha_suspension = VALUES(fecha_suspension),
           requiere_plan_mejora = VALUES(requiere_plan_mejora),
           creado_por = VALUES(creado_por),
           finalizado_en = VALUES(finalizado_en)`,
        [
          idEvaluacion,
          idFinca,
          `EV-${ev.id}`,
          toDateOnly(ev.fechaCreacion),
          toDateTime(ev.fechaCreacion),
          toDateTime(ev.fechaCierre),
          truncate(usuario, 255),
          ev.capitulo === 'C2' ? 'C2' : 'C1',
          TIPO_FINCA[finca.tipo] || null,
          SISTEMA_PRODUCTIVO[finca.sistema] || null,
          Math.max(0, safeNumber(finca.msnm)),
          total,
          Math.max(0, Math.trunc(safeNumber(muestra.calculada, total))),
          ajustada,
          muestra.justificacion || null,
          porcentaje,
          clasificacion,
          estado,
          ['EI', 'EII', 'EIII', 'EIV'].includes(ev.etapaActual) ? ev.etapaActual : 'EI',
          motivo,
          ev.suspension ? toDateTime(ev.suspension.fecha) : null,
          requierePlan,
          truncate(usuario, 150),
          toDateTime(ev.fechaCierre)
        ]
      );
      resumen.evaluaciones += 1;

      /* ------------------------ Respuestas ---------------------------- */
      await conn.execute(
        'DELETE FROM detalle_respuestas WHERE id_evaluacion = ?',
        [idEvaluacion]
      );

      for (const [codigo, r] of Object.entries(respuestas)) {
        if (!r || r.score === null || r.score === undefined) continue;
        const score = Number(r.score);
        if (!PUNTAJES.has(score)) continue;
        const ind = indMap.get(codigo);
        if (!ind) continue;

        await conn.execute(
          `INSERT INTO detalle_respuestas
             (id_detalle, id_evaluacion, id_indicador, puntaje_obtenido,
              requiere_tratamiento, registrado_por)
           VALUES (?, ?, ?, ?, ?, ?)`,
          [
            uuidFrom('detalle', `${ev.id}:${codigo}`),
            idEvaluacion,
            ind.id_indicador,
            score,
            Boolean(r.trat),
            truncate(usuario, 150)
          ]
        );
        resumen.respuestas += 1;
      }

      /* ------------------------- Resultados --------------------------- */
      await conn.execute(
        'DELETE FROM resultado_libertad WHERE id_evaluacion = ?',
        [idEvaluacion]
      );

      for (const item of resultadosNormalizados(ev, indMap)) {
        await conn.execute(
          `INSERT INTO resultado_libertad
             (id_resultado_libertad, id_evaluacion, id_libertad, promedio,
              ponderado, puntaje_bruto, cumplido)
           VALUES (?, ?, ?, ?, ?, ?, ?)`,
          [
            uuidFrom('resultado', `${ev.id}:${item.libertadId}`),
            idEvaluacion,
            item.numero,
            item.promedio,
            item.ponderado,
            item.promedio,
            item.cumplido
          ]
        );
        resumen.resultados += 1;
      }

      /* -------------------------- Documentos -------------------------- */
      await conn.execute(
        'DELETE FROM documento_soporte WHERE id_evaluacion = ?',
        [idEvaluacion]
      );

      for (const [codigoDoc, d] of Object.entries(ev.documental || {})) {
        const doc = docMap.get(codigoDoc);
        if (!doc) continue;
        const presenta = d.estado === 'presenta';
        const seNiega = d.estado === 'niega';

        await conn.execute(
          `INSERT INTO documento_soporte
             (id_documento_soporte, id_evaluacion, codigo_documento,
              tipo_documento, presenta, se_niega, firmado,
              matricula_comvezcol, observacion, creado_por)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
          [
            uuidFrom('documento', `${ev.id}:${codigoDoc}`),
            idEvaluacion,
            codigoDoc,
            truncate(doc.nombre, 150),
            presenta,
            seNiega,
            Boolean(d.firmado),
            d.matricula || null,
            d.obs || null,
            truncate(usuario, 150)
          ]
        );
        resumen.documentos += 1;
      }

      /* ------------------------ Plan de mejora ------------------------ */
      await conn.execute(
        'DELETE FROM plan_mejora WHERE id_evaluacion = ?',
        [idEvaluacion]
      );

      for (const [codigo, plan] of Object.entries(ev.plan || {})) {
        if (!plan || (!plan.accion && !plan.responsable && !plan.fecha)) continue;
        const ind = indMap.get(codigo);
        const respuesta = respuestas[codigo] || {};
        const score = respuesta.score === null || respuesta.score === undefined
          ? null
          : safeNumber(respuesta.score, null);
        const prioridad = respuesta.trat ? 'alta' : (score !== null && score <= 20 ? 'media' : 'baja');
        const titulo = truncate(
          `Mejora ${codigo}${ind ? ' — ' + ind.descripcion : ''}`,
          255
        );

        await conn.execute(
          `INSERT INTO plan_mejora
             (id_plan_mejora, id_evaluacion, id_indicador, id_libertad,
              titulo, accion, responsable, fecha_limite, prioridad,
              requiere_tratamiento, creado_por)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
          [
            uuidFrom('plan', `${ev.id}:${codigo}`),
            idEvaluacion,
            ind ? ind.id_indicador : null,
            ind ? ind.id_libertad : null,
            titulo,
            plan.accion || 'Acción pendiente de definir',
            plan.responsable || 'Por asignar',
            normalizeDate(plan.fecha),
            prioridad,
            Boolean(respuesta.trat),
            truncate(usuario, 150)
          ]
        );
        resumen.planes += 1;
      }
    }

    /* --------------------------- Sesión activa -------------------------- */
    const idFincaActiva = fincaUuid.get(String(state.fincaActivaId)) || null;
    const [sesiones] = await conn.execute(
      'SELECT id_sesion FROM sesion_trabajo WHERE usuario = ? AND activa = TRUE LIMIT 1',
      [usuario]
    );

    if (sesiones.length > 0) {
      await conn.execute(
        'UPDATE sesion_trabajo SET id_finca_activa = ? WHERE id_sesion = ?',
        [idFincaActiva, sesiones[0].id_sesion]
      );
    } else {
      await conn.execute(
        `INSERT INTO sesion_trabajo (id_sesion, usuario, id_finca_activa, activa)
         VALUES (?, ?, ?, TRUE)`,
        [crypto.randomUUID(), usuario, idFincaActiva]
      );
    }

    /* ---------------------------- Auditoría ----------------------------- */
    await conn.execute(
      `INSERT INTO auditoria_trazabilidad
         (id_auditoria, tabla_afectada, accion, usuario, valor_nuevo, observacion)
       VALUES (?, ?, 'UPDATE', ?, ?, ?)`,
      [
        crypto.randomUUID(),
        'estado_aplicacion',
        truncate(usuario, 150),
        JSON.stringify(resumen),
        'Sincronización automática del prototipo ICA'
      ]
    );

    const [snapRows] = await conn.execute(
      'SELECT version, actualizado_en FROM estado_aplicacion WHERE usuario = ?',
      [usuario]
    );

    await conn.commit();

    return {
      ...resumen,
      version: snapRows[0] ? snapRows[0].version : null,
      actualizado_en: snapRows[0] ? snapRows[0].actualizado_en : null
    };
  } catch (error) {
    await conn.rollback();
    throw error;
  } finally {
    conn.release();
  }
}

module.exports = {
  ensureSchema,
  syncState,
  uuidFrom
};
