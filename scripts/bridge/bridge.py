#!/usr/bin/env python3
# LAN command bridge: the Chromebook agent polls /<tok>/cmd, posts output, uploads files.
import os, sys, shutil
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs
D = os.path.dirname(os.path.abspath(__file__))
TOK = open(os.path.join(D, 'token')).read().strip()
HOST = sys.argv[1]
AGENT = r'''#!/bin/bash
B=http://%s:53317/%s
initctl stop powerd >/dev/null 2>&1
echo "bridge connected to $B (leave this running)"
while :; do
  curl -sf -m 15 -o /tmp/qc "$B/cmd" || { sleep 2; continue; }
  [ -s /tmp/qc ] || { sleep 1; continue; }
  id=$(head -1 /tmp/qc); { echo "B=$B"; tail -n +2 /tmp/qc; } > /tmp/qc.sh
  echo "running #$id"
  (cd /tmp; timeout 3600 bash /tmp/qc.sh) > /tmp/qc.out 2>&1; echo "[exit $?]" >> /tmp/qc.out
  curl -sf -m 120 --data-binary @/tmp/qc.out "$B/out?id=$id" >/dev/null
done
''' % (HOST, TOK)
class H(BaseHTTPRequestHandler):
    def log_message(self, f, *a): sys.stderr.write("%s %s\n" % (self.address_string(), f % a))
    def _parts(self):
        u = urlparse(self.path); p = u.path.strip('/').split('/', 1)
        if not p or p[0] != TOK: return None, None, None
        return (p[1] if len(p) > 1 else ''), parse_qs(u.query), u
    def _send(self, code, body=b'', ctype='text/plain'):
        self.send_response(code); self.send_header('Content-Type', ctype)
        self.send_header('Content-Length', str(len(body))); self.end_headers(); self.wfile.write(body)
    def do_GET(self):
        r, q, _ = self._parts()
        if r is None: return self._send(404)
        if r == 'agent.sh': return self._send(200, AGENT.encode())
        if r == 'cmd':
            qs = sorted((f for f in os.listdir(os.path.join(D, 'q')) if f.endswith('.sh')), key=lambda f: int(f[:-3]))
            if not qs: return self._send(200)
            f = os.path.join(D, 'q', qs[0]); body = (qs[0][:-3] + '\n').encode() + open(f, 'rb').read()
            os.rename(f, f + '.sent'); return self._send(200, body)
        if r.startswith('files/'):
            f = os.path.join(D, 'files', os.path.basename(r))
            if not os.path.isfile(f): return self._send(404)
            self.send_response(200); self.send_header('Content-Length', str(os.path.getsize(f))); self.end_headers()
            with open(f, 'rb') as fh: shutil.copyfileobj(fh, self.wfile)
            return
        self._send(404)
    def _body_to(self, path):
        n = int(self.headers.get('Content-Length', 0))
        with open(path + '.part', 'wb') as fh:
            while n > 0:
                b = self.rfile.read(min(n, 1 << 20))
                if not b: break
                fh.write(b); n -= len(b)
        os.rename(path + '.part', path)
    def do_POST(self):
        r, q, _ = self._parts()
        if r == 'out' and 'id' in q:
            self._body_to(os.path.join(D, 'out', os.path.basename(q['id'][0]) + '.txt')); return self._send(200, b'ok')
        self._send(404)
    def do_PUT(self):
        r, q, _ = self._parts()
        if r and r.startswith('up/'):
            self._body_to(os.path.join(D, 'up', os.path.basename(r))); return self._send(200, b'ok')
        self._send(404)
ThreadingHTTPServer(('0.0.0.0', 53317), H).serve_forever()
