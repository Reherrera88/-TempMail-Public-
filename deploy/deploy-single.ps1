<# 
.SYNOPSIS
Despliega TempMail @kards.cl en un SOLO servidor (VPS con iRedMail)

.DESCRIPTION
Despliegue simplificado: TempMail API + nginx en el mismo VPS donde corre iRedMail.
IMAP conecta a localhost:993. Puerto 8080 expuesto.

.NOTES
Requisitos: SSH acceso al VPS como root
Variables: IMAP_HOST=localhost (por defecto)
#>

param(
    [string]$VpsHost = "190.114.254.148",
    [string]$RemotePath = "/home/docker/tempmail",
    [string]$LocalPath = $PSScriptRoot  # Carpeta donde está este script (..\deploy)
)

# Resolver ruta base del proyecto
$ProjectRoot = Split-Path $LocalPath -Parent

Write-Host "=== TempMail Single-Server Deploy to VPS ===" -ForegroundColor Cyan
Write-Host "VPS: $VpsHost" -ForegroundColor Yellow

# 1. Copiar archivos estáticos (frontend)
Write-Host "`n[1/5] Copiando frontend estático..." -ForegroundColor Yellow
$staticSource = Join-Path $ProjectRoot "static"
ssh $VpsHost "mkdir -p $RemotePath"
scp -r "$staticSource/*" "$VpsHost:$RemotePath/"

# 2. Copiar nginx config SINGLE SERVER
Write-Host "`n[2/5] Copiando nginx config (single server)..." -ForegroundColor Yellow
$nginxConf = Join-Path $ProjectRoot "nginx\tempmail-single.conf"
scp "$nginxConf" "$VpsHost:$RemotePath/tempmail-single.conf"

# 3. Copiar docker-compose SINGLE SERVER
Write-Host "`n[3/5] Copiando docker-compose (single server)..." -ForegroundColor Yellow
$composeFile = Join-Path $ProjectRoot "docker-compose-single.yml"
scp "$composeFile" "$VpsHost:$RemotePath/docker-compose.yml"

# 4. Copiar CSV de cuentas (debe existir localmente)
Write-Host "`n[4/5] Copiando CSV de cuentas..." -ForegroundColor Yellow
$csvFile = Join-Path $ProjectRoot "cuentas_kards.csv"
if (Test-Path $csvFile) {
    scp "$csvFile" "$VpsHost:$RemotePath/cuentas_kards.csv"
} else {
    Write-Host "⚠️  CSV no encontrado localmente: $csvFile" -ForegroundColor Yellow
    Write-Host "   Asegúrate de tener cuentas_kards.csv en la raíz del proyecto" -ForegroundColor Yellow
}

# 5. Build y restart en VPS
Write-Host "`n[5/5] Building y starting contenedores en VPS..." -ForegroundColor Yellow
ssh $VpsHost @"
cd $RemotePath
docker compose -f docker-compose.yml build tempmail-api
docker compose -f docker-compose.yml up -d
docker compose -f docker-compose.yml ps
"@

# 6. Verificar healthcheck
Write-Host "`n[6/6] Verificando healthcheck..." -ForegroundColor Yellow
$health = ssh $VpsHost "curl -s http://localhost:5000/health"
if ($health -like '*ok*') {
    Write-Host "✅ Healthcheck OK: $health" -ForegroundColor Green
} else {
    Write-Host "❌ Healthcheck falló: $health" -ForegroundColor Red
    Write-Host "Revisa logs: ssh $VpsHost 'docker logs tempmail-api'" -ForegroundColor Red
}

Write-Host "`n=== Deploy Single-Server completado ===" -ForegroundColor Cyan
Write-Host "URL local: http://$VpsHost:8080" -ForegroundColor Cyan
Write-Host "Para ver logs: ssh $VpsHost 'docker logs -f tempmail-api'" -ForegroundColor Gray