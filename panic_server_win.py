"""
SGT Patrol — Panic Button Server (Windows)
==========================================
Runs on Windows, serves panic button page to phones on WiFi.
Sends panic events via UDP to WSL where ROS 2 publishes them.

Usage (in PowerShell):
    python panic_server_win.py
"""

from http.server import HTTPServer, BaseHTTPRequestHandler
import json
import socket
import time
import os
import ssl
from datetime import datetime, timedelta, timezone
from ipaddress import IPv4Address
from cryptography import x509
from cryptography.x509.oid import NameOID
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa

WSL_IP = '172.28.220.76'# WSL mirrored networking
WSL_PORT = 5001          # UDP port for panic events to WSL
#HTTP_PORT = 5000
HTTP_PORT = 8080
CERT_FILE = 'panic_server.crt'
KEY_FILE = 'panic_server.key'

PANIC_PAGE = """<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>SGT Patrol — Emergency</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
      background: #070f1a;
      color: #a8c8f0;
      font-family: -apple-system, sans-serif;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      min-height: 100vh;
      padding: 24px;
    }
    .logo { font-size: 11px; letter-spacing: 3px; color: #4a7fc1; margin-bottom: 48px; }
    .status { font-size: 13px; color: #4a6a8a; margin-bottom: 32px; text-align: center; min-height: 20px; }
    .panic-btn {
      width: 200px; height: 200px; border-radius: 50%;
      background: #2a0a0a; border: 3px solid #e74c3c;
      color: #e74c3c; font-size: 14px; font-weight: 600;
      letter-spacing: 2px; cursor: pointer;
      display: flex; flex-direction: column;
      align-items: center; justify-content: center; gap: 8px;
      transition: all 0.15s; -webkit-tap-highlight-color: transparent;
    }
    .panic-btn:active { background: #e74c3c; color: white; transform: scale(0.95); }
    .panic-btn:disabled { cursor: wait; }
    .panic-btn.sent { background: #0d2a1a; border-color: #2ecc71; color: #2ecc71; }
    .icon { font-size: 32px; }
    .note { margin-top: 48px; font-size: 11px; color: #2a4a6a; text-align: center; max-width: 280px; line-height: 1.6; }
  </style>
</head>
<body>
  <div class="logo">SGT PATROL</div>
  <div class="status" id="status">Checking GPS...</div>
  <button class="panic-btn" id="btn" onclick="sendPanic()">
    <span class="icon">🆘</span>
    <span>EMERGENCY</span>
  </button>
  <div class="note">Press in an emergency. Your location will be sent to the nearest patrol drone.</div>
  <script>
    let userLat = null, userLng = null;
    let gettingLocation = false;

    const btn = document.getElementById('btn');
    const status = document.getElementById('status');

    function setStatus(message) {
      status.textContent = message;
    }

    function requestLocation(onSuccess, onFailure) {
      if (gettingLocation) return;
      gettingLocation = true;

      const secure = window.isSecureContext ? 'YES' : 'NO';
      console.log('Secure context:', secure);
      console.log('Geolocation available:', !!navigator.geolocation);

      setStatus('Requesting iPhone GPS... HTTPS=' + secure);

      if (!navigator.geolocation) {
        gettingLocation = false;
        setStatus('GPS API NOT AVAILABLE in Safari.');
        if (onFailure) onFailure();
        return;
      }

      navigator.geolocation.getCurrentPosition(
        pos => {
          gettingLocation = false;
          userLat = pos.coords.latitude;
          userLng = pos.coords.longitude;

          console.log('GPS SUCCESS');
          console.log('Latitude:', userLat);
          console.log('Longitude:', userLng);
          console.log('Accuracy:', pos.coords.accuracy, 'meters');

          setStatus(
            'GPS OK: ' +
            userLat.toFixed(6) + ', ' +
            userLng.toFixed(6) +
            ' (±' + Math.round(pos.coords.accuracy) + 'm)'
          );

          if (onSuccess) onSuccess();
        },
        err => {
          gettingLocation = false;

          console.error('GPS ERROR CODE:', err.code);
          console.error('GPS ERROR MESSAGE:', err.message);

          let reason = '';

          if (err.code === 1) {
            reason = 'PERMISSION DENIED';
          } else if (err.code === 2) {
            reason = 'POSITION UNAVAILABLE';
          } else if (err.code === 3) {
            reason = 'GPS TIMEOUT';
          } else {
            reason = 'UNKNOWN GPS ERROR';
          }

          setStatus(
            'GPS FAILED: ' + reason +
            ' | code=' + err.code +
            ' | ' + (err.message || 'no message')
          );

          if (onFailure) onFailure();
        },
        {
          enableHighAccuracy: true,
          timeout: 30000,
          maximumAge: 0
        }
      );
    }

    function sendPanic() {
      if (
        userLat !== null &&
        userLng !== null &&
        Number.isFinite(userLat) &&
        Number.isFinite(userLng)
      ) {
        sendToServer();
        return;
      }

      btn.disabled = true;
      btn.style.opacity = '0.7';

      requestLocation(
        () => sendToServer(),
        () => {
          btn.disabled = false;
          btn.style.opacity = '1';
        }
      );
    }

    function sendToServer() {
      if (
        userLat === null ||
        userLng === null ||
        !Number.isFinite(userLat) ||
        !Number.isFinite(userLng)
      ) {
        btn.disabled = false;
        btn.style.opacity = '1';
        setStatus('NO VALID GPS — SOS NOT SENT.');
        return;
      }

      btn.disabled = true;
      btn.style.opacity = '0.7';
      setStatus('Sending emergency alert...');

      console.log('SENDING PANIC:', userLat, userLng);

      fetch('/panic', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          latitude: userLat,
          longitude: userLng,
          device: navigator.userAgent.substring(0, 50)
        })
      })
      .then(r => {
        if (!r.ok) throw new Error('Server returned ' + r.status);
        return r.json();
      })
      .then(() => {
        btn.classList.add('sent');
        btn.innerHTML = '<span class="icon">✓</span><span>HELP COMING</span>';
        setStatus(
          'SOS SENT! GPS: ' +
          userLat.toFixed(6) + ', ' +
          userLng.toFixed(6)
        );
      })
      .catch(err => {
        console.error('PANIC SEND ERROR:', err);
        btn.disabled = false;
        btn.style.opacity = '1';
        setStatus('SERVER ERROR: ' + err.message);
      });
    }

    // Start a GPS request when the page loads.
    requestLocation();
  </script>
</body>
</html>"""


def ensure_certificate():
    """Create a self-signed HTTPS certificate using Python cryptography."""
    if os.path.exists(CERT_FILE) and os.path.exists(KEY_FILE):
        print('[PANIC] Using existing HTTPS certificate.')
        return

    print('[PANIC] Creating local HTTPS certificate with Python...')

    key = rsa.generate_private_key(
        public_exponent=65537,
        key_size=2048
    )

    subject = issuer = x509.Name([
        x509.NameAttribute(NameOID.COUNTRY_NAME, 'ZA'),
        x509.NameAttribute(NameOID.ORGANIZATION_NAME, 'SGT Patrol'),
        x509.NameAttribute(NameOID.COMMON_NAME, '192.168.0.192'),
    ])

    now = datetime.now(timezone.utc)

    certificate = (
        x509.CertificateBuilder()
        .subject_name(subject)
        .issuer_name(issuer)
        .public_key(key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(now - timedelta(minutes=1))
        .not_valid_after(now + timedelta(days=3650))
        .add_extension(
            x509.SubjectAlternativeName([
                x509.IPAddress(IPv4Address('192.168.0.192'))
            ]),
            critical=False
        )
        .sign(key, hashes.SHA256())
    )

    with open(KEY_FILE, 'wb') as f:
        f.write(
            key.private_bytes(
                encoding=serialization.Encoding.PEM,
                format=serialization.PrivateFormat.TraditionalOpenSSL,
                encryption_algorithm=serialization.NoEncryption()
            )
        )

    with open(CERT_FILE, 'wb') as f:
        f.write(certificate.public_bytes(serialization.Encoding.PEM))

    print('[PANIC] HTTPS certificate created successfully.')
    print(f'[PANIC] Certificate: {os.path.abspath(CERT_FILE)}')
    print(f'[PANIC] Key:         {os.path.abspath(KEY_FILE)}')


class PanicHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass

    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-Type', 'text/html')
        self.end_headers()
        self.wfile.write(PANIC_PAGE.encode())

    def do_POST(self):
        if self.path == '/panic':
            length = int(self.headers.get('Content-Length', 0))
            body = json.loads(self.rfile.read(length))
            lat = body.get('latitude') or 0.0
            lng = body.get('longitude') or 0.0
            device = body.get('device', 'unknown')

            print(f'[PANIC] Button pressed — lat={lat}, lng={lng}, device={device[:30]}')

            # Send to WSL via UDP
            payload = json.dumps({
                'type': 'panic',
                'latitude': lat,
                'longitude': lng,
                'device_id': device,
                'timestamp': time.time() * 1000,
            }).encode()

            sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            sock.sendto(payload, (WSL_IP, WSL_PORT))
            sock.close()
            print(f'[PANIC] Sent to WSL ROS bridge at {WSL_IP}:{WSL_PORT}')

            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Access-Control-Allow-Origin', '*')
            self.end_headers()
            self.wfile.write(json.dumps({'status': 'dispatched'}).encode())

    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'POST, GET, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        self.end_headers()


if __name__ == '__main__':
    ensure_certificate()

    print(f'[PANIC] Starting HTTPS server on port {HTTP_PORT}')
    print(f'[PANIC] Open on your phone: https://192.168.0.192:{HTTP_PORT}')
    print(f'[PANIC] Forwarding panics to WSL at {WSL_IP}:{WSL_PORT}')

    server = HTTPServer(('0.0.0.0', HTTP_PORT), PanicHandler)

    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(certfile=CERT_FILE, keyfile=KEY_FILE)
    server.socket = context.wrap_socket(server.socket, server_side=True)

    server.serve_forever()