// ============================================================================
// Sincronización del prototipo con el servicio MariaDB
// - Descarga el estado del usuario al iniciar sesión.
// - Envía el estado a MariaDB después de cada cambio (con un pequeño retardo).
// - Si el servicio no está disponible, el prototipo sigue usando localStorage.
// - El archivo funciona igual sirviendo la app por HTTP o abriéndola con file://.
// ============================================================================

(function () {
  const API_BASE = window.ICA_API_BASE
    || (window.location.protocol === 'file:'
      ? 'http://127.0.0.1:3001/api'
      : '/api');

  const TIMEOUT_MS = 8000;
  let timer = null;
  let chain = Promise.resolve();
  let lastState = null;
  let lastUsuario = null;
  let lastLoad = { ok: false, found: false };

  function getStatusEl() {
    return document.getElementById('syncStatus');
  }

  function setStatus(text, kind) {
    const el = getStatusEl();
    if (!el) return;
    el.textContent = text;
    el.className = 'sync-status' + (kind ? ' ' + kind : '');
    el.title = 'Sincronización con MariaDB: ' + text
      + (kind === 'off' ? ' (haga clic para reintentar)' : '');
  }

  async function fetchConTimeout(url, opciones) {
    const control = new AbortController();
    const limite = setTimeout(() => control.abort(), TIMEOUT_MS);
    try {
      return await fetch(url, Object.assign({ cache: 'no-store' }, opciones, {
        signal: control.signal
      }));
    } finally {
      clearTimeout(limite);
    }
  }

  async function load(usuario) {
    if (!usuario) return null;
    setStatus('Cargando…', 'pending');
    try {
      const response = await fetchConTimeout(
        API_BASE + '/state?usuario=' + encodeURIComponent(usuario)
      );
      if (!response.ok) throw new Error('HTTP ' + response.status);
      const data = await response.json();
      if (data && data.state) {
        lastLoad = { ok: true, found: true };
        setStatus('Sincronizado', 'ok');
        return data.state;
      }
      lastLoad = { ok: true, found: false };
      setStatus('Nuevo en MariaDB', 'ok');
      return null;
    } catch (error) {
      lastLoad = { ok: false, found: false };
      console.warn('No se pudo cargar el estado desde MariaDB:', error);
      setStatus('Sin conexión', 'off');
      return null;
    }
  }

  async function send(state) {
    const usuario = state && state.user && state.user.name ? state.user.name : null;
    if (!usuario) return null;
    setStatus('Guardando…', 'pending');

    const response = await fetchConTimeout(API_BASE + '/state', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ usuario, state })
    });

    if (!response.ok) {
      const detalle = await response.text();
      throw new Error('HTTP ' + response.status + ': ' + detalle);
    }

    const data = await response.json();
    setStatus('Sincronizado', 'ok');
    window.dispatchEvent(new CustomEvent('ica:synced', { detail: data }));
    return data;
  }

  function queue(state, immediate) {
    if (!state || !state.user || !state.user.name) return;
    lastState = state;
    lastUsuario = state.user.name;
    clearTimeout(timer);
    setStatus('Guardando…', 'pending');

    timer = setTimeout(() => {
      // Se toma una copia en el momento de enviar para no serializar un objeto
      // que siga cambiando mientras la petición está en curso.
      const snapshot = JSON.parse(JSON.stringify(state));
      chain = chain
        .then(() => send(snapshot))
        .catch(error => {
          console.warn('No se pudo sincronizar el estado con MariaDB:', error);
          setStatus('Sin conexión', 'off');
        });
    }, immediate ? 0 : 600);
  }

  function flush() {
    if (timer) {
      clearTimeout(timer);
      timer = null;
    }
    if (lastState && lastUsuario) {
      const snapshot = JSON.parse(JSON.stringify(lastState));
      chain = chain
        .then(() => send(snapshot))
        .catch(error => {
          console.warn('No se pudo sincronizar el estado con MariaDB:', error);
          setStatus('Sin conexión', 'off');
        });
    }
  }

  function discard() {
    if (timer) {
      clearTimeout(timer);
      timer = null;
    }
    lastState = null;
    lastUsuario = null;
    setStatus('Sin sesión', '');
  }

  window.ICA_SYNC = {
    apiBase: API_BASE,
    load,
    queue,
    flush,
    discard,
    send,
    status: setStatus,
    get lastLoad() { return lastLoad; }
  };

  window.addEventListener('online', () => {
    if (lastState) queue(lastState, true);
  });

  window.addEventListener('beforeunload', () => {
    if (!lastState || !lastUsuario) return;
    const payload = JSON.stringify({ usuario: lastUsuario, state: lastState });
    if (navigator.sendBeacon) {
      // text/plain evita el preflight CORS cuando la app se abre con file://.
      navigator.sendBeacon(
        API_BASE + '/state',
        new Blob([payload], { type: 'text/plain;charset=UTF-8' })
      );
    }
  });

  document.addEventListener('DOMContentLoaded', () => {
    const el = getStatusEl();
    if (!el) return;
    el.addEventListener('click', () => {
      if (lastState) queue(lastState, true);
    });
  });
})();
