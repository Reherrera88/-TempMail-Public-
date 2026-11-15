# TempMail @kards.cl

> **Plataforma web para acceso rápido a 200 cuentas de correo temporales** — sin contraseña, solo IMAP, desplegada localmente en Pi-ter.

[![Deploy](https://img.shields.io/badge/deploy-Pi--ter%20%7C%20Docker-blue)](https://github.com/Reherrera88/-TempMail-Public-)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)
[![Python](https://img.shields.io/badge/python-3.12%2B-blue)](https://python.org)
[![Flask](https://img.shields.io/badge/flask-3.0.3-lightgrey)](https://flask.palletsprojects.com)

---

## ¿Qué es?

**TempMail** es una interfaz web que permite visualizar los correos de **200 buzones temporales @kards.cl** sin necesidad de autenticación manual. El backend (Flask) gestiona las conexiones IMAP al servidor de correo (iRedMail/Dovecot en VPS configurable via `IMAP_HOST`) y expone una API REST. El frontend (vanilla JS + CSS) presenta un grid buscable con vista de emails en modal.

**Características clave:**
- Sin login de usuario — auto-login via credenciales en backend
- 200 cuentas formato `nombre+apellido+XXX@kards.cl` (aleatorias)
- 10 MB cuota por cuenta
- Solo IMAP SSL desde IP Pi-ter (configurable via `PI_TER_IP`) — SMTP/POP3/Roundcube bloqueados
- Dockerizado — backend API + nginx estático
- Solo red local — `http://<PI_TER_IP>:8080` (sin Cloudflare Tunnel)

---

## Arquitectura

```
+-----------------------------------------------------------------+
|                        USUARIO (NAVEGADOR)                       |
|                    http://<PI_TER_IP>:8080                        |
+-----------------------------------------------------------------+
                                  |
                                  v
+-----------------------------------------------------------------+
|  PI-TER (<PI_TER_IP>)                                           |
|  +-------------------------------------------------------------+  |
|  | web-tempmail-nginx (nginx:alpine) — Puerto 8080             |  |
|  |   +--- /*          > static/index.html (frontend)           |  |
|  |   +--- /api/*      > proxy a Flask API :5000                |  |
|  +-------------------------------------------------------------+  |
|                                  |                               |
|                                  v                               |
|  +-------------------------------------------------------------+  |
|  | web-tempmail-api (Python 3.12 + Flask) — Puerto 5000        |  |
|  |   +--- GET /api/accounts          > lista 200 cuentas       |  |
|  |   +--- GET /api/emails/<email>    > ultimos 30 emails       |  |
|  |   +--- GET /api/email/<email>/<uid> > email completo        |  |
|  |   +--- IMAP SSL > <IMAP_HOST>:993 (Dovecot iRedMail)        |  |
|  +-------------------------------------------------------------+  |
+-----------------------------------------------------------------+
                                  |
                                  v
+-----------------------------------------------------------------+
|  VPS MAIL SERVER (<IMAP_HOST>)                                  |
|  iRedMail (dev/master) — Debian 13                              |
|  Dovecot IMAP SSL (puerto 993)                                  |
|  +-------------------------------------------------------------+  |
|  | 200 cuentas @kards.cl — IMAP only desde <PI_TER_IP>         |  |
|  |  Cuota: 10 MB | Hash: SSHA512 | Maildir: /var/vmail/        |  |
|  +-------------------------------------------------------------+  |
+-----------------------------------------------------------------+
```

**Variables de entorno:** Configura `PI_TER_IP` (IP local de Pi-ter) e `IMAP_HOST` (IP del VPS mail) en tu entorno.

---

## Despliegue Rapido (Pi-ter)

### Prerrequisitos
- Pi-ter accesible via SSH (`pi-ter` en `.ssh/config` o IP `<PI_TER_IP>`)
- Docker + Docker Compose instalados en Pi-ter
- Red `web-network` externa creada: `docker network create web-network`

### 1. Preparar directorios y CSV
```bash
ssh pi-ter
sudo mkdir -p /home/docker/containers/web/tempmail
sudo cp ~/cuentas_kards.csv /home/docker/containers/web/tempmail/
```

### 2. Copiar archivos del proyecto
```bash
# Desde tu maquina local (repo TempMail)
scp -r static/* pi-ter:/home/docker/containers/web/tempmail/
scp nginx/tempmail-local.conf pi-ter:/home/docker/containers/web/nginx-conf/
scp docker-compose-local.yml pi-ter:/home/docker/containers/web/docker-compose-tempmail.yml
```

### 3. Build y deploy
```bash
ssh pi-ter
cd /home/docker/containers/web
docker compose -f docker-compose-tempmail.yml build web-tempmail-api
docker compose -f docker-compose-tempmail.yml up -d
```

### 4. Verificar
```bash
# Health check
curl http://<PI_TER_IP>:8080/health
# > {"status":"ok","accounts":200}

# Listar cuentas
curl http://<PI_TER_IP>:8080/api/accounts

# Frontend
# Abrir en navegador: http://<PI_TER_IP>:8080
```

---

## Desarrollo Local

```bash
# Clonar repo
git clone https://github.com/Reherrera88/-TempMail-Public-.git
cd -TempMail-Public-

# Entorno virtual
python -m venv venv
source venv/bin/activate  # Windows: venv\Scripts\activate

# Dependencias
pip install -r requirements.txt

# CSV de cuentas (copiar sample o generar uno)
cp cuentas_kards.sample.csv cuentas_kards.csv

# Variables de entorno
export IMAP_HOST=<IP_DEL_VPS_MAIL>
export IMAP_PORT=993
export CSV_PATH=./cuentas_kards.csv

# Ejecutar
python app.py
# Abrir http://localhost:5000
```

---

## API Endpoints

| Metodo | Endpoint | Descripcion |
|--------|----------|-------------|
| GET | `/health` | Health check + cuenta de accounts |
| GET | `/api/accounts` | Lista 200 cuentas ([{email}]) |
| GET | `/api/emails/<email>?limit=20&offset=0` | Ultimos emails de una cuenta |
| GET | `/api/email/<email>/<uid>` | Email completo por UID |

### Ejemplos

```bash
# Health
curl http://<PI_TER_IP>:8080/health

# Todas las cuentas
curl http://<PI_TER_IP>:8080/api/accounts

# Emails de una cuenta (paginado)
curl "http://<PI_TER_IP>:8080/api/emails/thiago%2Bvinas%2B539%40kards.cl?limit=10&offset=0"

# Email completo
curl "http://<PI_TER_IP>:8080/api/email/thiago%2Bvinas%2B539%40kards.cl/12345"
```

### Respuesta `/api/emails/<email>`
```json
{
  "emails": [
    {
      "subject": "Bienvenido a TempMail",
      "from": "noreply@example.com",
      "date": "15/11/2026 10:30",
      "preview": "Este es un correo de prueba...",
      "body": "Cuerpo completo del mensaje..."
    }
  ],
  "total": 5,
  "limit": 20,
  "offset": 0
}
```

---

## Seguridad y Restricciones

### Nivel Mail Server (VPS `<IMAP_HOST>`)
Configurado para las 200 cuentas `@kards.cl` temporales:

| Protocolo | Acceso | Detalle |
|-----------|--------|---------|
| IMAP SSL (993) | Solo `<PI_TER_IP>` | `allow_nets=<PI_TER_IP>` en Dovecot passdb/userdb |
| SMTP AUTH (25/587/465) | Bloqueado | `smtpd_sender_restrictions` + `check_sender_access` |
| POP3/POP3S (110/995) | Bloqueado | Dovecot protocol config |
| Roundcube (webmail) | Bloqueado | Sin credenciales validas para login |
| ManageSieve | Bloqueado | Dovecot protocol config |

### Nivel Aplicacion (Pi-ter)
- CSV montado **read-only** (`:ro`) en contenedor API
- Usuario **no-root** en Dockerfile (`appuser` UID 1000)
- **Healthcheck** activo cada 30s
- Sin autenticacion en frontend (red local confiable)
- **CORS** habilitado en Flask para desarrollo

---

## Estructura del Repositorio

```
-TempMail-Public/
+--- app.py                      # Backend Flask + IMAP
+--- requirements.txt            # flask, flask-cors
+--- Dockerfile                  # Multi-stage, non-root, healthcheck
+--- docker-compose-local.yml    # Compose para Pi-ter (local only)
+--- cuentas_kards.sample.csv    # Ejemplo de formato CSV (3 cuentas demo)
+--- nginx/
|    +--- tempmail.conf          # Config produccion (Cloudflare Tunnel)
|    +--- tempmail-local.conf    # Config local (puerto 8080, sin Tunnel)
+--- static/
|    +--- index.html             # Frontend vanilla JS + CSS (dark mode)
+--- deploy/
|    +--- README.md              # Guia completa de despliegue
|    +--- deploy.ps1             # Script PowerShell automatizado
+--- .github/workflows/ci.yml    # CI/CD GitHub Actions
+--- .gitignore                  # Excluye CSV real, venv, secrets, OS files
+--- LICENSE                     # MIT License
+--- README.md                   # Este archivo
```

> **Seguridad:** El archivo real `cuentas_kards.csv` con 200 cuentas y contrasenas **NO esta en el repo público** (excluido por `.gitignore`). En produccion, genera tu propio CSV y montalo como volume read-only. Ver seccion "Generar CSV de cuentas".

---

## Frontend - Funcionalidades

- Grid responsivo 200 tarjetas (auto-fill, minmax 280px)
- Busqueda en tiempo real (debounce 150ms) por nombre/apellido/email
- Modal de emails con paginacion (30 por pagina)
- Vista completa de email (headers + body text/html)
- Contador de emails carga background (primeras 20 cuentas)
- Dark mode nativo (CSS custom properties)
- Accesible (ARIA, keyboard nav, prefers-reduced-motion)
- Zero dependencies JS (vanilla ES6+)

---

## Configuracion (Variables de Entorno)

| Variable | Default | Descripcion |
|----------|---------|-------------|
| `IMAP_HOST` | `<IP_DEL_VPS_MAIL>` | Host del servidor IMAP (Dovecot) |
| `IMAP_PORT` | `993` | Puerto IMAP SSL |
| `CSV_PATH` | `/app/cuentas_kards.csv` | Ruta al CSV de credenciales |

---

## Generar y Actualizar CSV de Cuentas

### Formato requerido
El CSV debe tener **exactamente 2 columnas**: `email,password`

```csv
email,password
nombre+apellido+XXX@kards.cl,password_aleatoria_16_chars
ejemplo+garcia+123@kards.cl,AbCdEf12!@#$%^&*
test+rodriguez+456@kards.cl,XyZ789wXyZ789wXy
```

Ver archivo de ejemplo: `cuentas_kards.sample.csv`

### Generar 200 cuentas aleatorias (script Python)

```python
# generate_accounts.py
import csv, random, string

nombres = ["carlos", "maria", "jose", "juan", "luis", "ana", "miguel", "laura", "pedro", "sofia", ...]
apellidos = ["garcia", "rodriguez", "gonzalez", "fernandez", "lopez", "martinez", "sanchez", "perez", ...]

with open('cuentas_kards.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['email', 'password'])
    emails = set()
    while len(emails) < 200:
        nombre = random.choice(nombres)
        apellido = random.choice(apellidos)
        numero = random.randint(1, 999)
        email = f"{nombre}+{apellido}+{numero:03d}@kards.cl"
        if email not in emails:
            emails.add(email)
            password = ''.join(random.choices(string.ascii_letters + string.digits + '!@#$%', k=16))
            writer.writerow([email, password])

print("Generadas 200 cuentas en cuentas_kards.csv")
```

### Desplegar CSV en Pi-ter (produccion)

```bash
# 1. Generar CSV localmente con el script anterior
python generate_accounts.py

# 2. Copiar a Pi-ter
scp cuentas_kards.csv pi-ter:/home/docker/containers/web/tempmail/

# 3. Reiniciar API
ssh pi-ter "docker restart web-tempmail-api"
```

### En desarrollo local

```bash
# Copiar sample o generar uno
cp cuentas_kards.sample.csv cuentas_kards.csv
# O generar con script arriba
export CSV_PATH=./cuentas_kards.csv
python app.py
```

---

## Troubleshooting

| Problema | Diagnostico | Solucion |
|----------|-------------|----------|
| API 500 "Error IMAP: Authentication failed" | Credenciales invalidas o IP no permitida | Verificar CSV, Dovecot `allow_nets`, contrasenas en iRedAdmin |
| Cuenta no encontrada (404) | CSV no montado o email mal formateado | Verificar volume mount `:ro`, encoding URL (`+` > `%2B`) |
| CORS error | Origen no permitido | Backend ya tiene `flask-cors` habilitado (`*`) |
| Timeout emails grandes | `proxy_read_timeout` bajo | Aumentar en nginx (`proxy_read_timeout 60s;`) |
| Contenedor no inicia | Puerto 5000 ocupado / CSV corrupto | `docker logs web-tempmail-api`, validar CSV |

### Logs utiles
```bash
# API logs
ssh pi-ter "docker logs -f web-tempmail-api"

# Nginx logs
ssh pi-ter "docker logs -f web-tempmail-nginx"
ssh pi-ter "tail -f /var/log/nginx/tempmail_access.log"
```

---

## Documentacion Relacionada

- Wiki entidad > `[[entities/tempmail-platform.md]]` (arquitectura completa)
- Wiki cuentas > `[[entities/kards-cl-temp-accounts.md]]` (200 cuentas, restricciones)
- Mail Server > `[[entities/mail-server-vps.md]]` (infraestructura iRedMail)
- DNS records > `DNS_RECORDS_FOR_AARON.md` (Cloudflare para kards.cl)

---

## Autores y Agentes

| Rol | Agente | Responsabilidad |
|-----|--------|-----------------|
| Frontend + Backend + Docker + Deploy | **Aaron** | Paginas web en Pi-ter (Cloudflare Tunnel, Docker, nginx) |
| Mail Server + Restricciones IMAP | **Deamon** | Infraestructura homelab (VPS, Dovecot, Postfix, DNS) |
| DNS Cloudflare | **Aaron** | Registros A, MX, SPF, DKIM, DMARC para kards.cl |

---

## Licencia

MIT License — Libre uso, modificacion y distribucion.

---

## Enlaces

- **Repo:** https://github.com/Reherrera88/-TempMail-Public-
- **Wiki:** https://github.com/Reherrera88/wiki_opencode
- **Deploy local:** http://<PI_TER_IP>:8080
- **Mail Server:** https://mail.conectarte.cl/iredadmin/

---

> **Nota:** El nombre del repositorio comienza con guion (`-TempMail-Public-`) por convención del usuario. En GitHub se accede como `https://github.com/Reherrera88/-TempMail-Public-`.