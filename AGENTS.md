# AGENTS.md

## What this repo is

- Single-page, no-build prototype (HTML + CSS + vanilla JS) of the ICA equine animal-welfare evaluation system. Auth is fake and the UI is local-first: every change is saved in `localStorage`; optionally the full state is also synced to MariaDB. The other outbound call is the optional Gemini plan, which goes through the `/api/gemini` proxy (or directly to Google with a user-supplied key).
- **The core app must keep working by opening `index.html` directly (`file://`) and offline.** Only the AI plan needs the server or an own key; MariaDB sync is optional and must fail silently. Do not introduce npm, bundlers, frameworks, ES modules in the frontend, or CDN dependencies. `js/html2pdf.bundle.min.js` is vendored for this reason. The Gemini proxy uses native modules only; `mysql2` is isolated to the database service (`server/db-api.js`) and must never be loaded in the browser.
- UI text, docs, and most identifiers are Spanish (Colombia). Keep new user-facing copy in Spanish.

## Run and verify

- Run offline: double-click `index.html`, or `Start-Process .\index.html`.
- Run with local MariaDB: start MariaDB on port 3307, `Copy-Item .env.example .env`, `npm install` once, then `npm run db-api` and open `http://127.0.0.1:3001`. The same process serves the SPA and `/api/state`.
- For the AI plan without a user key and/or the containerized database, run the Docker deployment: `Copy-Item .env.example .env` (set `GEMINI_API_KEY` if needed), then `docker compose up --build` and open `http://localhost:8080`.
- Syntax check (there is no test/lint/build suite): `npm run check` (runs `node --check` over the frontend, API and adapters). Equivalent manual checks: `node --check js/data.js`, `node --check js/app.js`, `node --check js/sync.js`, `node --check server/db-api.js`, `node --check server/sync-service.js`, `node --check server/proxy.js`, `node --check api/gemini.js`, `node --check functions/api/gemini.js` and `node --check server/gemini-core.mjs`.
- Seed/reset local UI data: in DevTools run `localStorage.removeItem('ica_equidos_v3')`, then reload. Reset MariaDB operational data only with the SQL scripts/documented admin flow; do not delete catalog rows.
- Manual smoke path: login (any credentials) → create farm (becomes active) → add inventory group → new evaluation → Etapa I (add a potrero/corral) → Etapa II scores → Etapa III documents → Etapa IV finalize/PDF. With `npm run db-api`, verify the chip reaches **Sincronizado** and `/api/health` returns MariaDB 13.x on port 3307.

## Architecture

- `index.html` contains every screen. Each is `<section id="screen<Name>" class="screen">`; navigation uses `data-screen="<Name>"`, and `showScreen()` has an explicit `if` for each screen's render function. A new screen needs all three.
- `js/data.js` is the normative/runtime source of truth: freedoms, weights, indicator catalog, documents, sample table, scoring. Loaded first as classic globals.
- `js/app.js` holds `state`, persistence (`ica_equidos_v3`), render functions, and delegated `click`/`change` handlers (`data-action`, `data-plan`, etc.). Renders replace `innerHTML`, so dynamic controls must use delegation.
- `js/sync.js` is optional and independent: it loads/queues the full state against `/api/state`, updates `#syncStatus`, retries on `online`, and uses `navigator.sendBeacon` on unload. It must never block rendering or throw if the API is absent.
- `server/db-api.js` is the only npm-dependent process (`mysql2`). It serves `/api/health`, `/api/state` (GET/POST) and `/api/resumen`, and also serves the static SPA for local development on port 3001. `server/sync-service.js` stores the JSON snapshot in `estado_aplicacion` and projects it onto the normalized V3 tables with deterministic UUIDs.
- `db/init/01-modelo.sql` is the MariaDB V3 schema/seed and `db/init/02-sync.sql` adds `estado_aplicacion` and the `ica_app` user. Docker runs them only when the database volume is first created.
- `data/ica_catalogo.json` is an exported snapshot. **The app never fetches it**; editing it alone changes nothing. No generator is checked in, so keep it in sync manually when changing the catalog.
- `README_PROTOCOLO.md` documents behavior; `PROMPT_MOCKUP.md` is only copy-paste prompts for design tools, not runtime code.

## Domain rules that are easy to break

- Fixed by the ICA V2.0 (2023) norm: 5 freedoms weighted **20/15/30/15/20 %**, **C1 = 43** and **C2 = 32** indicators, scores only **0/20/55/100**, classification **≥90 Excelente, 75–89 Alto, 50–74 Medio, <50 Bajo**. The norm wins over user stories/docs on conflict.
- Catalog entries are keyed by **description text** in two places: `GUIA` and `DOCUMENTOS[].indicador`. Renaming a description silently breaks its methodology/questions or document mapping. `DESC.L*` order also matters because `FASE_DOCUMENTAL` selects documentary indicators by array index.
- `buildCapitulo` cycles `DESC.L*` with `i % pool.length`; if a `CONTEO` value ever exceeds its pool, descriptions repeat and the description-keyed lookups become ambiguous.
- C2 has no “Transporte sin hacinamiento” indicator, so document D7 deliberately shows “no aplica en este capítulo”.
- Documentary indicators: their score `<select>` is disabled by design; score comes from the documents table. “Se niega” forces score 0 + requires treatment; “Presenta” sets 100 only when unscored or 0.
- Scoring: each freedom averages **only scored** indicators (unscored are excluded, not zero), then applies the freedom weight. A freedom with no scored indicators contributes 0, but partially scoring a freedom is not penalized.
- Sample size (Tabla 1): <10 → all animals; 11–20 → 10; 21–99 → 20; 100–499 → 30; 500–999 → 40; ≥1000 → `ceil(5 %)`. Zero animals returns 0.

## Persistence gotchas

- Etapa I/II/III edits are **not autosaved**: scores and document fields persist only when their save button runs `capturarRespuestas`/`capturarDocumental`. The improvement-plan inputs are the exception and save on `change`.
- Etapa I requires at least one potrero/corral; incomplete Etapa II or finalization only shows a confirmation warning.
- `renderEvaluacion()` assigns `ev.resultados` as a render side effect (not saved); history/plan may recompute from answers.
- `saveState()` writes `localStorage` first and then calls `ICA_SYNC.queue(state)` only when `state.user` exists. `loadState()` is async: it restores local data and, if a user is present, replaces it with the remote state when available. Login also loads the remote state and starts clean when MariaDB explicitly reports no state for that user. Logout calls `ICA_SYNC.discard()` before clearing `state.user`.
- The login username is the MariaDB sync key. `sesion_trabajo` stores the active farm per user; a generated `usuario_activo` column + unique index emulates a partial unique index. Do not rewrite these to plain `UNIQUE(usuario)` without handling the active/inactive history.
- `estado_aplicacion` keeps the exact JSON shape needed by the UI. The normalized tables are a projection for queries; if sync fails, the UI must still work from `localStorage`.

## MariaDB sync

- `POST /api/state` expects `{ usuario, state }`. `server/sync-service.js` writes the full JSON to `estado_aplicacion` and then, in one transaction, upserts deterministic IDs for `fincas`, `inventario_equino`, `evaluaciones`, `detalle_respuestas`, `resultado_libertad`, `documento_soporte`, `plan_mejora`, `sesion_trabajo` and `auditoria_trazabilidad`. Re-posting the same state must not duplicate rows (version increments).
- The API reads the DB from env: `DB_HOST`, `DB_PORT`, `DB_USER`, `DB_PASSWORD`, `DB_NAME`, plus `DB_API_HOST`/`DB_API_PORT`. Local defaults target `127.0.0.1:3307`; Docker Compose overrides the host to the `db` service on `3306`.
- `ensureSchema()` only checks `estado_aplicacion`; it does not create the 17-table model. The host `ica_app` user intentionally lacks `CREATE`, so import `db/init/01-modelo.sql` and `db/init/02-sync.sql` first. In Docker, the init scripts run on first volume creation.
- When changing the app state shape, update both `server/sync-service.js` projections and the SQL model. `estado_aplicacion.estado_json` must remain the exact object the frontend can rehydrate.
- Do not import SQL with `Get-Content | mariadb` on Windows (it can break UTF-8). Use `mariadb.exe < archivo.sql` from `cmd` or the documented scripts; keep accents and `ñ` intact.

## Gemini AI plan

- `generar-plan-ia` (Etapa IV and “Plan de mejora”) calls `generarPlanIA()`. The normal path uses the server proxy `/api/gemini`, whose key lives only in the `GEMINI_API_KEY` environment variable. A user key is optional (advanced mode) and stored unencrypted in `localStorage` under `ica_gemini_api_key`; never commit or log either key.
- Hybrid mode in `solicitarPlanGemini()`: with a saved user key the browser calls Google directly and sends `x-goog-api-key`; without one it sends `{ modelo, payload }` to `/api/gemini`. If a saved key is rejected (401/403), it is cleared and the same request is retried through the proxy. On `file://` without a key, the UI explains that the server is required.
- The request sends compact structured JSON from `construirDatosEvaluacionIA()` to the `GEMINI_MODELS` list (`gemini-2.5-flash`, `gemini-2.5-flash-lite`, `gemini-2.0-flash`), not the rendered PDF. The payload carries the global/per-freedom numeric summary, only indicators scored below 75, and only documents whose state is not "Presenta". It retries 429/500/503 once (1.5 s wait) and falls back to the next model on 404/503. The result is saved separately as `ev.planIA`, leaving the manual `ev.plan` intact.
- Errors produced by the proxy itself carry `error.origen = 'proxy_ica'` (missing key, rate limit, invalid model/payload); they stop the loop immediately and show the server message. Upstream Google errors are passed through unchanged and keep the normal retry/fallback behavior.
- Each Gemini `fetch` runs under an `AbortController` with a `GEMINI_TIMEOUT_MS` (15 s) limit, cleared in `finally`. A timeout does not retry the same model: it moves straight to the next one; if every model times out, the toast reports the 15 s limit and the last model tried.
- `generationConfig` requests `thinkingConfig: { thinkingLevel: 'LOW' }` to keep latency low. If a model rejects that field with HTTP 400, the same request is retried once without `thinkingConfig`; an unrelated 400 is not retried. The loading button shows the elapsed seconds.
- The AI response is re-filtered against the evaluation before saving and again when rendering (`filtrarHallazgosIA` / `filtrarDocumentosIA`): only indicators whose real score is below 75 and documents whose real state is not "Presenta" are shown, even for plans generated before the filter existed.
- PDF export sets `pagebreak: { mode: ['css', 'legacy'], avoid: [...] }` and the CSS uses `break-inside: avoid` so findings cards, table rows, and summary/recommendation blocks are not split across pages.
- PDF export reuses `exportPdf()`/html2pdf. Elements marked `data-pdf-ignore` (for example the AI toolbar) are hidden during export.

## Gemini proxy and deployment

- `POST /api/gemini` accepts `{ modelo, payload }`. `server/gemini-core.mjs` is the shared, dependency-free core: allowed-model list, 15 requests/minute/IP sliding window, 256 KB body limit, 20 s upstream timeout, and the call to `https://generativelanguage.googleapis.com/v1beta/models/<modelo>:generateContent?key=...`.
- Adapters: `server/proxy.js` (Node `http` server, `PORT` default 3000, binds `127.0.0.1` by default) serves both `/api/gemini` and `/api/gemini/health`; `api/gemini.js` is the Vercel function; `functions/api/gemini.js` is the Cloudflare Pages Function. Rate limiting is in-memory and per instance (best effort in serverless).
- Docker: the image installs `nodejs`/`npm` on `nginx:alpine`, runs `npm ci --omit=dev` for `mysql2`, and starts the Gemini proxy from `/docker-entrypoint.d/40-gemini-proxy.sh` and the MariaDB API from `/docker-entrypoint.d/41-db-api.sh`. `nginx/default.conf` proxies `^~ /api/gemini` to `127.0.0.1:3000` and `^~ /api/` to `127.0.0.1:3001`, and exposes only the static app. `docker-compose.yml` passes `GEMINI_API_KEY` and DB credentials from the environment/`.env`, and starts a MariaDB 11.4 service initialized from `db/init/`. `.env.example` documents the variables; `.gitignore` excludes `.env` and `.dockerignore` keeps it out of the build context.
- The Docker DB user has broad privileges on the isolated `ica_equidos` database in the container; the host `ica_app` user is limited to `SELECT/INSERT/UPDATE/DELETE`. Keep that distinction when changing grants.
- The key is never served by Nginx, never embedded in the frontend, and never written to `localStorage` unless a user explicitly saves an own key in “Configuración avanzada: usar clave propia”.
