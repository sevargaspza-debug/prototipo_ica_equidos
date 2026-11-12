FROM nginx:alpine

# Node.js se usa para el proxy /api/gemini y para la API de MariaDB.
# mysql2 es la única dependencia npm; el frontend sigue siendo HTML/CSS/JS puro.
RUN apk add --no-cache nodejs npm

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force

# Configuración de Nginx con el proxy hacia los procesos Node locales.
COPY nginx/default.conf /etc/nginx/conf.d/default.conf

# Solo se publican los archivos estáticos; el código del servidor no se sirve.
COPY index.html /usr/share/nginx/html/
COPY css /usr/share/nginx/html/css
COPY js /usr/share/nginx/html/js
COPY assets /usr/share/nginx/html/assets
COPY data /usr/share/nginx/html/data

COPY server /app/server
COPY docker/40-gemini-proxy.sh /docker-entrypoint.d/40-gemini-proxy.sh
COPY docker/41-db-api.sh /docker-entrypoint.d/41-db-api.sh
RUN chmod +x /docker-entrypoint.d/40-gemini-proxy.sh /docker-entrypoint.d/41-db-api.sh

# 3000 = proxy Gemini · 3001 = API MariaDB (Nginx los publica en /api).
ENV PORT=3000
ENV DB_API_PORT=3001
ENV DB_API_HOST=127.0.0.1
EXPOSE 80
