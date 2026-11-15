<# 
.SYNOPSIS
Despliega TempMail @kards.cl a Servidor Frontend (multi-server legacy)

.DESCRIPTION
Copia archivos estáticos, reconstruye contenedor API y reinicia servicios.
Usa docker-compose-local.yml y nginx tempmail-local.conf (puerto 8080, sin Cloudflare Tunnel).
Este script es para despliegue Legacy (Frontend Server + VPS Mail separados).

.NOTES
Requisitos: SSH key configurada para <FRONTEND_HOST>
Variables de entorno: IMAP_HOST (IP del VPS mail)
#>

param(
    [string]$FrontendHost = "<FRONTEND_HOST>",
    [string]$RemotePath = "/home/docker/containers/web",
    [string]$LocalPath = $PSScriptRoot  # Carpeta donde está este script (..\deploy)
)

# Resolver ruta base del proyecto
$ProjectRoot = Split-Path $LocalPath -Parent

Write-Host "=== TempMail Deploy to Frontend Server (Legacy) ===" -ForegroundColor Cyan

# 1. Copiar archivos estáticos (frontend)
Write-Host "`n[1/5] Copiando frontend estático..." -ForegroundColor Yellow
$staticSource = Join-Path $ProjectRoot "static"
$staticDest = "$RemotePath/tempmail"
ssh $FrontendHost "mkdir -p $staticDest"
scp -r "$staticSource/*" "$FrontendHost:$staticDest/"

# 2. Copiar nginx config LOCAL (puerto 8080)
Write-Host "`n[2/5] Copiando nginx config local..." -ForegroundColor Yellow
$nginxConf = Join-Path $ProjectRoot "nginx\tempmail-local.conf"
scp "$nginxConf" "$FrontendHost:$RemotePath/nginx-conf/tempmail-local.conf"

# 3. Copiar docker-compose LOCAL
Write-Host "`n[3/5] Copiando docker-compose local..." -ForegroundColor Yellow
$composeFile = Join-Path $ProjectRoot "docker-compose-local.yml"
scp "$composeFile" "$FrontendHost:$RemotePath/docker-compose-tempmail.yml"

# 4. Rebuild y restart en Frontend Server
Write-Host "`n[4/5] Rebuilding y restarting contenedores en Frontend Server..." -ForegroundColor Yellow
ssh $FrontendHost @"
cd $RemotePath
docker compose -f docker-compose-tempmail.yml build web-tempmail-api
docker compose -f docker-compose-tempmail.yml up -d web-tempmail-api web-tempmail-nginx
docker compose -f docker-compose-tempmail.yml ps
"@

# 5. Verificar healthcheck
Write-Host "`n[5/5] Verificando healthcheck..." -ForegroundColor Yellow
$health = ssh $FrontendHost "curl -s http://localhost:5000/health"
if ($health -like '*ok*') {
    Write-Host "✅ Healthcheck OK: $health" -ForegroundColor Green
} else {
    Write-Host "❌ Healthcheck falló: $health" -ForegroundColor Red
    Write-Host "Revisa logs: ssh $FrontendHost 'docker logs web-tempmail-api'" -ForegroundColor Red
}

Write-Host "`n=== Deploy completado ===" -ForegroundColor Cyan
Write-Host "URL local: http://<FRONTEND_IP>:8080" -ForegroundColor Cyan
Write-Host "Para ver logs: ssh $FrontendHost 'docker logs -f web-tempmail-api'" -ForegroundColor Gray