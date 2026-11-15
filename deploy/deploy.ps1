<# 
.SYNOPSIS
Despliega TempMail @kards.cl a Pi-ter (producción)

.DESCRIPTION
Copia archivos estáticos, reconstruye contenedor API y reinicia servicios.

.NOTES
Requisitos: SSH key configurada para pi-ter (usuario aaron)
#>

param(
    [string]$PiTerHost = "pi-ter",
    [string]$RemotePath = "/home/docker/containers/web",
    [string]$LocalPath = "C:\Users\reherrera88\Documents\OpenCode\Aaron\tempmail"
)

Write-Host "=== TempMail Deploy to Pi-ter ===" -ForegroundColor Cyan

# 1. Copiar archivos estáticos (frontend)
Write-Host "`n[1/4] Copiando frontend estático..." -ForegroundColor Yellow
$staticSource = Join-Path $LocalPath "static"
$staticDest = "$RemotePath/tempmail"
ssh $PiTerHost "mkdir -p $staticDest"
scp -r "$staticSource/*" "$PiTerHost:$staticDest/"

# 2. Copiar nginx config
Write-Host "`n[2/4] Copiando nginx config..." -ForegroundColor Yellow
$nginxConf = Join-Path $LocalPath "nginx\tempmail.conf"
scp "$nginxConf" "$PiTerHost:$RemotePath/nginx-conf/tempmail.conf"

# 3. Copiar docker-compose actualizado
Write-Host "`n[3/4] Copiando docker-compose.yml..." -ForegroundColor Yellow
$composeFile = Join-Path (Split-Path $LocalPath) "web\docker-compose.yml"
scp "$composeFile" "$PiTerHost:$RemotePath/docker-compose.yml"

# 4. Rebuild y restart en Pi-ter
Write-Host "`n[4/4] Rebuilding y restarting contenedores en Pi-ter..." -ForegroundColor Yellow
ssh $PiTerHost @"
cd $RemotePath
docker compose build web-tempmail-api
docker compose up -d web-tempmail-api web-tempmail-nginx
docker compose ps
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
Write-Host "URL: https://tempmail.conectarte.cl" -ForegroundColor Cyan
Write-Host "Para ver logs: ssh $PiTerHost 'docker logs -f web-tempmail-api'" -ForegroundColor Gray