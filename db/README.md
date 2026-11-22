# Base de datos del prototipo ICA

Esta carpeta contiene los scripts que usa la implementación Docker y que
también sirven para una instalación manual en MariaDB.

## Contenido

- `init/01-modelo.sql`: modelo relacional V3 (17 tablas, 6 vistas, catálogos y
  semillas de 75 indicadores, 7 documentos y 13 mapeos).
- `init/02-sync.sql`: tabla `estado_aplicacion` y usuario de aplicación
  `ica_app` para la instancia local.

## Docker

`docker compose up --build` levanta MariaDB 11.4 y ejecuta los scripts de
`init/` solo la primera vez que se crea el volumen `ica_equidos_db`.

Para reiniciar la base desde cero:

```powershell
docker compose down -v
docker compose up --build
```

## Instalación manual en la MariaDB del equipo

```powershell
& "C:\Program Files\MariaDB 13.0\bin\mariadb.exe" -h 127.0.0.1 -P 3307 -u root -p < db\init\01-modelo.sql
& "C:\Program Files\MariaDB 13.0\bin\mariadb.exe" -h 127.0.0.1 -P 3307 -u root -p < db\init\02-sync.sql
```

La contraseña de `ica_app` es local (`IcaApp2026!` por defecto). Cámbiela en
`02-sync.sql`, en `.env` y en `docker-compose.yml` antes de exponer el servicio
fuera del equipo.
