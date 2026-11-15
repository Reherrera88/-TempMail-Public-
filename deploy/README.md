# TempMail @kards.cl — Deployment Guide

## Descripción
Página web para acceso rápido a 200 cuentas de correo temporales @kards.cl sin necesidad de contraseña. Backend Flask + IMAP a iRedMail (Dovecot) en VPS 190.114.254.148.

## Arquitectura
```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│  Cloudflare     │────▶│  nginx (Pi-ter)  │────▶│  Flask API      │
│  Tunnel         │     │  web-tempmail-   │     │  web-tempmail-  │
│  tempmail.      │     │  nginx           │     │  api            │
│  conectarte.cl  │     │                  │     │  (IMAP → ired)  │
└─────────────────┘     └──────────────────┘     └─────────────────┘
                              │
                              ▼
                      /usr/share/nginx/html/tempmail/index.html
```

## Componentes

| Componente | Contenedor | Puerto | Descripción |
|------------|------------|--------|-------------|
| Frontend (static) | `web-tempmail-nginx` | 80 | Sirve index.html + assets |
| Backend API | `web-tempmail-api` | 5000 | Flask + IMAP a iRedMail |
| Proxy nginx | `web-tempmail-nginx` | 80 | `/api/*` → backend |

## Despliegue en Pi-ter (producción)

### 1. Preparar directorios en la Pi
```bash
ssh pi-ter
sudo mkdir -p /home/docker/containers/web/tempmail
sudo cp ~/cuentas_kards.csv /home/docker/containers/web/tempmail/
```

### 2. Copiar archivos estáticos a la Pi
```bash
# Desde tu máquina local (Aaron project)
scp -r tempmail/static/* pi-ter:/home/docker/containers/web/tempmail/
```

### 3. Actualizar docker-compose y reconstruir
```bash
ssh pi-ter
cd /home/docker/containers/web
# Copiar el nuevo docker-compose.yml y nginx-conf/tempmail.conf
docker compose -f docker-compose.yml build web-tempmail-api
docker compose -f docker-compose.yml up -d
```

### 4. Verificar
```bash
# Healthcheck API
curl http://localhost:5000/health

# Ver logs
docker logs web-tempmail-api
docker logs web-tempmail-nginx

# Probar API
curl http://localhost/api/accounts
curl "http://localhost/api/emails/thiago+vinas+539@kards.cl?limit=5"
```

### 5. Cloudflare Tunnel
Agregar en Cloudflare Zero Trust → Networks → Tunnels → pi-ter:
- Subdomain: `tempmail`
- Domain: `conectarte.cl`
- Service: `HTTP://web-tempmail-nginx:80`

URL final: **https://tempmail.conectarte.cl**

## Desarrollo local

```bash
cd tempmail
python -m venv venv
source venv/bin/activate
pip install -r requirements.txt
cp ../Deamon/cuentas_kards.csv .
python app.py
# Abrir http://localhost:5000
```

## API Endpoints

| Método | Endpoint | Descripción |
|--------|----------|-------------|
| GET | `/api/accounts` | Lista 200 cuentas (sin passwords) |
| GET | `/api/emails/<email>?limit=20&offset=0` | Últimos correos de una cuenta |
| GET | `/api/email/<email>/<uid>` | Correo completo por UID |
| GET | `/health` | Healthcheck |

## Estructura de archivos en Pi-ter

```
/home/docker/containers/web/
├── docker-compose.yml
├── nginx-conf/
│   ├── 00-charset.conf
│   └── tempmail.conf
├── tempmail/
│   ├── cuentas_kards.csv          # Montado en API (ro) — GENERAR LOCALMENTE
│   ├── index.html                 # Frontend servido por nginx
│   └── ... (assets)
```

> **⚠️ Importante:** El archivo `cuentas_kards.csv` con 200 cuentas reales y contraseñas **NO está en el repo público**. Debes generarlo localmente y copiarlo a Pi-ter.

## Generar y desplegar CSV de cuentas

### 1. Generar CSV localmente
```bash
# Opción A: Usar script Python (ver README.md principal sección "Generar CSV")
python generate_accounts.py

# Opción B: Copiar y editar el sample
cp cuentas_kards.sample.csv cuentas_kards.csv
# Editar con 200 cuentas reales
```

### 2. Desplegar a Pi-ter
```bash
scp cuentas_kards.csv pi-ter:/home/docker/containers/web/tempmail/
ssh pi-ter "docker restart web-tempmail-api"
```

### 3. Verificar
```bash
ssh pi-ter "curl -s http://localhost:5000/health"
# → {"status":"ok","accounts":200}
```

## Troubleshooting

| Problema | Solución |
|----------|----------|
| API 500 "Error IMAP" | Verificar conectividad a 190.114.254.148:993 desde contenedor |
| Cuenta no encontrada | Verificar CSV montado correctamente en `/app/cuentas_kards.csv` |
| CORS error | Backend ya tiene `flask-cors` habilitado |
| Timeout en emails grandes | Aumentar `proxy_read_timeout` en nginx |

## Seguridad
- CSV montado **read-only** en contenedor API
- Usuario no-root en Dockerfile
- Healthcheck activo
- Headers de seguridad en nginx
- Sin contraseñas en frontend (solo en backend via CSV)

## Mantenimiento
- Backups CSV: `\\10.0.0.10\Backups\pi-ter` (keep-3, cada 2 días)
- Logs nginx: `/var/log/nginx/tempmail_*.log`
- Sync GitHub: `sudo /usr/local/bin/pi-ter-sync-git.sh` desde `/opt/pi-ter-config`