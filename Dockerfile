# Multi-stage build para TempMail backend
FROM python:3.12-alpine AS builder

WORKDIR /app

# Dependencias de build
RUN apk add --no-cache gcc musl-dev libffi-dev openssl-dev

# Instalar dependencias Python
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# Stage final
FROM python:3.12-alpine

WORKDIR /app

# Copiar dependencias instaladas
COPY --from=builder /install /usr/local

# Crear usuario no-root
RUN adduser -D -H -s /sbin/nologin appuser

# Copiar aplicación
COPY app.py .
COPY static/ ./static()

# Copiar CSV de ejemplo (en producción se monta el real como volume read-only)
COPY cuentas_kards.sample.csv ./cuentas_kards.csv

# Permisos
RUN chown -R appuser:appuser /app

USER appuser

EXPOSE 5000

# Healthcheck
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD wget -qO- http://localhost:5000/health || exit 1

CMD ["python", "app.py"]