# TempMail @kards.cl — Deployment Guide

## Descripcion
Pagina web para acceso rapido a 200 cuentas de correo temporales @kards.cl sin necesidad de contrasena. Backend Flask + IMAP a iRedMail (Dovecot) en VPS configurable via `IMAP_HOST`.

## Opcion A: Despliegue en un Solo Servidor (VPS + iRedMail + TempMail) — RECOMENDADO

Si el servidor de correo (iRedMail) y TempMail corren en el **mismo VPS**, el deploy es mas simple:

### Ventajas
- IMAP a `localhost:993` (sin latencia, sin firewall extra)
- Un solo servidor que mantener
- Menos configuracion de red
- Puerto 8080 unico expuesto

### Arquitectura Single Server
```
+---------------------+     +----------------------+     +-----------------+
|   USUARIO           |---->|  nginx (VPS)         |---->|  Flask API      |
|   http://<VPS_IP>   |     |  tempmail-nginx      |     |  tempmail-api   |
|   :8080             |     |  :8080               |     |  :5000          |
+---------------------+     +----------------------+     |  (IMAP local) |
                                |                        +-----------------+
                                v
                       /usr/share/nginx/html/tempmail/index.html
                       
IMAP -> localhost:993 (Dovecot iRedMail en mismo VPS)
```

### 1. Preparar en el VPS
```bash
# En el VPS (donde corre iRedMail)
mkdir -p /home/docker/tempmail
cp cuentas_kards.csv /home/docker/tempmail/

# Copiar archivos del proyecto
scp -r static/* root@<VPS_IP>:/home/docker/tempmail/
scp nginx/tempmail-single.conf root@<VPS_IP>:/home/docker/tempmail/
scp docker-compose-single.yml root@<VPS_IP>:/home/docker/tempmail/
```

### 2. Build y deploy
```bash
ssh root@<VPS_IP>
cd /home/docker/tempmail
docker compose -f docker-compose-single.yml build tempmail-api
docker compose -f docker-compose-single.yml up -d
```

### 3. Verificar
```bash
curl http://<VPS_IP>:8080/health
# > {"status":"ok","accounts":200}

# Frontend: http://<VPS_IP>:8080
```

---

## Opcion B: Despliegue Separado (Frontend Server + VPS Mail) — Legacy

### Arquitectura (Local only - sin Cloudflare Tunnel)
```
+---------------------+     +----------------------+     +-----------------+
|   USUARIO           |---->|  nginx (Frontend)    |---->|  Flask API      |
|   http://<FRONTEND_IP>|    |  tempmail-nginx      |     |  tempmail-api   |
|   :8080             |     |  :8080               |     |  :5000          |
+---------------------+     +----------------------+     |  (IMAP -> ired) |
                                |                        +-----------------+
                                v
                       /usr/share/nginx/html/tempmail/index.html
                       
Variables: <FRONTEND_IP> = IP del servidor frontend, <IMAP_HOST> = IP del VPS mail
```

## Componentes

| Componente | Contenedor | Puerto | Descripcion |
|------------|------------|--------|-------------|
| Frontend (static) | `tempmail-nginx` | 8080 | Sirve index.html + assets |
| Backend API | `tempmail-api` | 5000 | Flask + IMAP a iRedMail |
| Proxy nginx | `tempmail-nginx` | 8080 | `/api/*` -> backend |

## Despliegue en Frontend Server (produccion)

### 1. Preparar directorios en el Servidor Frontend
```bash
ssh <FRONTEND_HOST>
sudo mkdir -p /home/docker/containers/web/tempmail
sudo cp ~/cuentas_kards.csv /home/docker/containers/web/tempmail/
```

### 2. Copiar archivos estaticos al Servidor Frontend
```bash
# Desde tu maquina local (Aaron project)
scp -r tempmail/static/* <FRONTEND_HOST>:/home/docker/containers/web/tempmail/
```

### 3. Actualizar docker-compose y reconstruir
```bash
ssh <FRONTEND_HOST>
cd /home/docker/containers/web
# Copiar el nuevo docker-compose.yml y nginx-conf/tempmail-local.conf
docker compose -f docker-compose-tempmail.yml build web-tempmail-api
docker compose -f docker-compose-tempmail.yml up -d
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

**Nota:** Sin Cloudflare Tunnel. Acceso via `http://<FRONTEND_IP>:8080`

## Desarrollo local

```bash
cd tempmail
python -m venv venv
source venv/bin/activate
pip install -r requirements.txt
cp cuentas_kards.sample.csv cuentas_kards.csv
python app.py
# Abrir http://localhost:5000
```

## API Endpoints

| Metodo | Endpoint | Descripcion |
|--------|----------|-------------|
| GET | `/api/accounts` | Lista 200 cuentas (sin passwords) |
| GET | `/api/emails/<email>?limit=20&offset=0` | Ultimos correos de una cuenta |
| GET | `/api/email/<email>/<uid>` | Correo completo por UID |
| GET | `/health` | Healthcheck |

## Estructura de archivos en Servidor Frontend

```
 /home/docker/containers/web/
+--- docker-compose.yml
+--- nginx-conf/
|    +--- 00-charset.conf
|    +--- tempmail-local.conf
+--- tempmail/
|    +--- cuentas_kards.csv          # Montado en API (ro) -- GENERAR LOCALMENTE
|    +--- index.html                 # Frontend servido por nginx
|    +--- ... (assets)
```

> **Importante:** El archivo `cuentas_kards.csv` con 200 cuentas reales y contrasenas **NO esta en el repo publico**. Debes generarlo localmente y copiarlo al Servidor Frontend.

## Generar y desplegar CSV de cuentas

### 1. Generar CSV localmente
```bash
# Opcion A: Usar script Python (ver README.md principal seccion "Generar CSV")
python generate_accounts.py

# Opcion B: Copiar y editar el sample
cp cuentas_kards.sample.csv cuentas_kards.csv
# Editar con 200 cuentas reales
```

### 2. Desplegar al Servidor Frontend
```bash
scp cuentas_kards.csv <FRONTEND_HOST>:/home/docker/containers/web/tempmail/
ssh <FRONTEND_HOST> "docker restart web-tempmail-api"
```

### 3. Verificar
```bash
ssh <FRONTEND_HOST> "curl -s http://localhost:5000/health"
# > {"status":"ok","accounts":200}
```

## Troubleshooting

| Problema | Solucion |
|----------|----------|
| API 500 "Error IMAP" | Verificar conectividad a <IMAP_HOST>:993 desde contenedor |
| Cuenta no encontrada | Verificar CSV montado correctamente en `/app/cuentas_kards.csv` |
| CORS error | Backend ya tiene `flask-cors` habilitado |
| Timeout en emails grandes | Aumentar `proxy_read_timeout` en nginx |

## Seguridad

- CSV montado **read-only** en contenedor API
- Usuario no-root en Dockerfile
- Healthcheck activo
- Headers de seguridad en nginx
- Sin contrasenas en frontend (solo en backend via CSV)

## Mantenimiento

- Backups CSV: `\\<BACKUP_SERVER_IP>\Backups\pi-ter` (keep-3, cada 2 dias)
- Logs nginx: `/var/log/nginx/tempmail_*.log`
- Sync GitHub: `sudo /usr/local/bin/pi-ter-sync-git.sh` desde `/opt/pi-ter-config`