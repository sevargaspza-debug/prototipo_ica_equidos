#!/bin/sh
# Inicia la API de MariaDB en segundo plano. Nginx publica /api/state,
# /api/health y /api/resumen hacia este proceso (127.0.0.1:3001).
set -e

node /app/server/db-api.js &
