#!/usr/bin/env python3
"""
Backend Flask para acceso a correos temporales @kards.cl
Conecta vía IMAP a iRedMail (Dovecot) y expone API REST.
"""
import os
import csv
import imaplib
import email
from email.header import decode_header
from datetime import datetime
from functools import lru_cache
from flask import Flask, jsonify, request, send_from_directory
from flask_cors import CORS

app = Flask(__name__, static_folder='static')
CORS(app)

# Configuración del servidor de correo
IMAP_HOST = os.getenv('IMAP_HOST', '190.114.254.148')
IMAP_PORT = int(os.getenv('IMAP_PORT', '993'))
# CSV path: en producción /app/cuentas_kards.csv, en dev relativo al script
CSV_PATH = os.getenv('CSV_PATH', os.path.join(os.path.dirname(__file__), 'cuentas_kards.csv'))

# Caché de conexiones IMAP por cuenta (máx 10 concurrentes)
_imap_cache = {}

def load_accounts():
    """Carga las cuentas desde el CSV."""
    accounts = []
    with open(CSV_PATH, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            accounts.append({
                'email': row['email'].strip(),
                'password': row['password'].strip()
            })
    return accounts

ACCOUNTS = load_accounts()

def get_imap_connection(email_addr, password):
    """Obtiene o crea conexión IMAP para una cuenta."""
    key = email_addr
    if key in _imap_cache:
        try:
            # Verificar si la conexión sigue viva
            _imap_cache[key].noop()
            return _imap_cache[key]
        except:
            del _imap_cache[key]
    
    # Nueva conexión
    imap = imaplib.IMAP4_SSL(IMAP_HOST, IMAP_PORT)
    imap.login(email_addr, password)
    imap.select('INBOX')
    
    # Limpiar caché si hay muchas conexiones
    if len(_imap_cache) >= 10:
        oldest = next(iter(_imap_cache))
        try:
            _imap_cache[oldest].logout()
        except:
            pass
        del _imap_cache[oldest]
    
    _imap_cache[key] = imap
    return imap

def decode_mime_header(header):
    """Decodifica cabeceras MIME (subject, from, etc.)."""
    if not header:
        return ''
    parts = decode_header(header)
    decoded = []
    for part, encoding in parts:
        if isinstance(part, bytes):
            decoded.append(part.decode(encoding or 'utf-8', errors='replace'))
        else:
            decoded.append(part)
    return ' '.join(decoded)

def parse_email(msg):
    """Extrae información relevante de un mensaje email."""
    # Subject
    subject = decode_mime_header(msg.get('Subject', ''))
    
    # From
    from_header = decode_mime_header(msg.get('From', ''))
    
    # Date
    date_str = msg.get('Date', '')
    try:
        date_obj = email.utils.parsedate_to_datetime(date_str)
        date_formatted = date_obj.strftime('%d/%m/%Y %H:%M')
    except:
        date_formatted = date_str
    
    # Body (preferir text/plain, fallback text/html)
    body = ''
    if msg.is_multipart():
        for part in msg.walk():
            content_type = part.get_content_type()
            disposition = str(part.get('Content-Disposition', ''))
            if 'attachment' not in disposition:
                if content_type == 'text/plain':
                    payload = part.get_payload(decode=True)
                    if payload:
                        body = payload.decode(part.get_content_charset() or 'utf-8', errors='replace')
                        break
                elif content_type == 'text/html' and not body:
                    payload = part.get_payload(decode=True)
                    if payload:
                        body = payload.decode(part.get_content_charset() or 'utf-8', errors='replace')
    else:
        payload = msg.get_payload(decode=True)
        if payload:
            body = payload.decode(msg.get_content_charset() or 'utf-8', errors='replace')
    
    # Truncar body para preview
    body_preview = body[:300].replace('\n', ' ').replace('\r', ' ').strip()
    if len(body) > 300:
        body_preview += '...'
    
    return {
        'subject': subject,
        'from': from_header,
        'date': date_formatted,
        'preview': body_preview,
        'body': body  # completo para vista detallada
    }

@app.route('/api/accounts')
def api_accounts():
    """Lista todas las cuentas (sin contraseñas)."""
    return jsonify([{'email': a['email']} for a in ACCOUNTS])

@app.route('/api/emails/<path:email_addr>')
def api_emails(email_addr):
    """Obtiene los últimos correos de una cuenta."""
    # Buscar cuenta
    account = next((a for a in ACCOUNTS if a['email'] == email_addr), None)
    if not account:
        return jsonify({'error': 'Cuenta no encontrada'}), 404
    
    # Parámetros
    limit = min(int(request.args.get('limit', 20)), 50)
    offset = int(request.args.get('offset', 0))
    
    try:
        imap = get_imap_connection(account['email'], account['password'])
        
        # Buscar todos los mensajes (más recientes primero)
        status, messages = imap.search(None, 'ALL')
        if status != 'OK':
            return jsonify({'error': 'Error buscando mensajes'}), 500
        
        msg_nums = messages[0].split()
        if not msg_nums:
            return jsonify({'emails': [], 'total': 0})
        
        # Ordenar por fecha descendente (más nuevos primero)
        # IMAP devuelve en orden ascendente, así que invertimos
        msg_nums = msg_nums[::-1]
        
        # Aplicar paginación
        paginated = msg_nums[offset:offset + limit]
        
        emails = []
        for num in paginated:
            status, data = imap.fetch(num, '(RFC822)')
            if status != 'OK':
                continue
            raw = data[0][1]
            msg = email.message_from_bytes(raw)
            emails.append(parse_email(msg))
        
        return jsonify({
            'emails': emails,
            'total': len(msg_nums),
            'limit': limit,
            'offset': offset
        })
    
    except imaplib.IMAP4.error as e:
        # Invalidar caché en error de auth
        if email_addr in _imap_cache:
            del _imap_cache[email_addr]
        return jsonify({'error': f'Error IMAP: {str(e)}'}), 500
    except Exception as e:
        return jsonify({'error': f'Error interno: {str(e)}'}), 500

@app.route('/api/email/<path:email_addr>/<msg_uid>')
def api_email_detail(email_addr, msg_uid):
    """Obtiene un correo completo por UID."""
    account = next((a for a in ACCOUNTS if a['email'] == email_addr), None)
    if not account:
        return jsonify({'error': 'Cuenta no encontrada'}), 404
    
    try:
        imap = get_imap_connection(account['email'], account['password'])
        status, data = imap.fetch(msg_uid, '(RFC822)')
        if status != 'OK':
            return jsonify({'error': 'Mensaje no encontrado'}), 404
        
        raw = data[0][1]
        msg = email.message_from_bytes(raw)
        return jsonify(parse_email(msg))
    
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/')
def index():
    return send_from_directory('static', 'index.html')

@app.route('/<path:path>')
def static_files(path):
    return send_from_directory('static', path)

@app.route('/health')
def health():
    return jsonify({'status': 'ok', 'accounts': len(ACCOUNTS)})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=False)