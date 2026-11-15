<# 
.SYNOPSIS
Despliega TempMail @kards.cl a Pi-ter (local only)

.DESCRIPTION
Copia archivos estáticos, reconstruye contenedor API y reinicia servicios.
Usa docker-compose-local.yml y nginx tempmail-local.conf (puerto 8080, sin Cloudflare Tunnel).

.NOTES
Requisitos: SSH key configurada para pi-ter
Variables de entorno: IMAP_HOST (IP del VPS mail)
#>

param(
    [string]$PiTerHost = "pi-ter",
    [string]$RemotePath = "/home/docker/containers/web",
    [string]$LocalPath = $PSScriptRoot  # Carpeta donde está este script (..\deploy)
)

# Resolver ruta base del proyecto
$ProjectRoot = Split-Path $LocalPath -Parent

Write-Host "=== TempMail Deploy to Pi-ter (Local) ===" -ForegroundColor Cyan

# 1. Copiar archivos estáticos (frontend)
Write-Host "`n[1/5] Copiando frontend estático..." -ForegroundColor Yellow
$staticSource = Join-Path $ProjectRoot "static"
$staticDest = "$RemotePath/tempmail"
ssh $PiTerHost "mkdir -p $staticDest"
scp -r "$staticSource/*" "$PiTerHost:$staticDest/"

# 2. Copiar nginx config LOCAL (puerto 8080)
Write-Host "`n[2/5] Copiando nginx config local..." -ForegroundColor Yellow
$nginxConf = Join-Path $ProjectRoot "nginx\tempmail-local.conf"
scp "$nginxConf" "$PiTerHost:$RemotePath/nginx-conf/tempmail-local.conf"

# 3. Copiar docker-compose LOCAL
Write-Host "`n[3/5] Copiando docker-compose local..." -ForegroundColor Yellow
$composeFile = Join-Path $ProjectRoot "docker-compose-local.yml"
scp "$composeFile" "$PiTerHost:$RemotePath/docker-compose-tempmail.yml"

# 4. Rebuild y restart en Pi-ter
Write-Host "`n[4/5] Rebuilding y restarting contenedores en Pi-ter..." -ForegroundColor Yellow
ssh $PiTerHost @"
cd $RemotePath
docker compose -f docker-compose-tempmail.yml build web-tempmail-api
docker compose -f docker-compose-tempmail.yml up -d web-tempmail-api web-tempmail-nginx
docker compose -f docker-compose-tempmail.yml ps
"@

# 5. Verificar healthcheck
Write-Host "`n[5/5] Verificando healthcheck..." -ForegroundColor Yellow
$health = ssh $PiTerHost "curl -s http://localhost:5000/health"
if ($health -like '*ok*') {
    Write-Host "✅ Healthcheck OK: $health" -ForegroundColor Green
} else {
    Write-Host "❌ Healthcheck falló: $health" -ForegroundColor Red
    Write-Host "Revisa logs: ssh $PiTerHost 'docker logs web-tempmail-api'" -ForegroundColor Red
}

Write-Host "`n=== Deploy completado ===" -ForegroundColor Cyan
Write-Host "URL local: http://<PI_TER_IP>:8080" -ForegroundColor Cyan
Write-Host "Para ver logs: ssh $PiTerHost 'docker logs -f web-tempmail-api'" -ForegroundColor Gray