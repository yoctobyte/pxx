#!/usr/bin/env python3
"""testserver.py DIR PORTFILE CERTDIR [ADDR]: the server curl's test.sh talks to.

Three listeners on 127.0.0.1, ports written to PORTFILE as `http N`,
`https-ec N`, `https-rsa N` (and `http-byname N` on ADDR, a loopback address
/etc/hosts gives a name, so curl must resolve it): plain HTTP, and HTTPS with the EC and the RSA
server certificate from CERTDIR (ec.crt/ec.key, rsa.crt/rsa.key, made by
test.sh and signed by its throwaway CA). HTTP/1.1, so several URLs in one curl
run reuse the connection. Stdlib only. Runs until killed.

  GET/HEAD /f/NAME    DIR/NAME with Content-Length (Range honoured)
  GET/HEAD /tree/PATH DIR/PATH, a path with directories (git's test.sh
                      serves a repository so, for git's dumb HTTP); no `..`
  GET /chunked/NAME   the same bytes, chunked transfer encoding
  POST|PUT /echo      "len SHA256" of the request body
  GET /redir/N        302 chain N long, ending at /f/small.txt
  GET /hdr            the request's X-Test, Cookie, Authorization, Range,
                      Content-Type and Accept headers, one per line
  GET /setcookie      sets two cookies
  GET /code/N         status N with a short body
"""
import hashlib
import http.server
import os
import ssl
import sys
import threading

ROOT, PORTFILE, CERTS = sys.argv[1], sys.argv[2], sys.argv[3]
BYNAME = sys.argv[4] if len(sys.argv) > 4 else ""   # a loopback address /etc/hosts names


class H(http.server.BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def log_message(self, *a):
        pass

    def send(self, code, body, ctype='text/plain', extra=()):
        self.send_response(code)
        self.send_header('Content-Type', ctype)
        self.send_header('Content-Length', str(len(body)))
        for k, v in extra:
            self.send_header(k, v)
        self.end_headers()
        if self.command != 'HEAD':
            self.wfile.write(body)

    def file(self, name):
        p = os.path.join(ROOT, os.path.basename(name))
        if not os.path.isfile(p):
            return None
        with open(p, 'rb') as f:
            return f.read()

    def do_HEAD(self):
        self.do_GET()

    def tree(self, rel):
        parts = [x for x in rel.split('?')[0].split('/') if x not in ('', '.')]
        if '..' in parts:
            return None
        p = os.path.join(ROOT, *parts) if parts else ROOT
        if not os.path.isfile(p):
            return None
        with open(p, 'rb') as f:
            return f.read()

    def do_GET(self):
        p = self.path
        if p.startswith('/tree/'):
            data = self.tree(p[6:])
            if data is None:
                return self.send(404, b'no such file\n')
            return self.send(200, data, 'application/octet-stream')
        if p.startswith('/f/'):
            data = self.file(p[3:])
            if data is None:
                return self.send(404, b'no such file\n')
            rng = self.headers.get('Range')
            if rng and rng.startswith('bytes='):
                a, _, b = rng[6:].partition('-')
                a = int(a)
                b = int(b) if b else len(data) - 1
                part = data[a:b + 1]
                return self.send(206, part, 'application/octet-stream',
                                 [('Content-Range', 'bytes %d-%d/%d' % (a, a + len(part) - 1, len(data)))])
            return self.send(200, data, 'application/octet-stream')
        if p.startswith('/chunked/'):
            data = self.file(p[9:])
            if data is None:
                return self.send(404, b'no such file\n')
            self.send_response(200)
            self.send_header('Content-Type', 'application/octet-stream')
            self.send_header('Transfer-Encoding', 'chunked')
            self.end_headers()
            step = 7919
            for i in range(0, len(data), step):
                c = data[i:i + step]
                self.wfile.write(b'%x\r\n' % len(c) + c + b'\r\n')
            self.wfile.write(b'0\r\n\r\n')
            return
        if p.startswith('/redir/'):
            n = int(p[7:] or 0)
            loc = '/redir/%d' % (n - 1) if n > 1 else '/f/small.txt'
            return self.send(302, b'moved\n', extra=[('Location', loc)])
        if p == '/hdr':
            out = ''
            for k in ('X-Test', 'Cookie', 'Authorization', 'Range', 'Content-Type', 'Accept'):
                out += '%s: %s\n' % (k, self.headers.get(k))
            return self.send(200, out.encode())
        if p == '/setcookie':
            return self.send(200, b'cookies set\n', extra=[('Set-Cookie', 'a=1; Path=/'),
                                                          ('Set-Cookie', 'b=two; Path=/')])
        if p.startswith('/code/'):
            n = int(p[6:])
            return self.send(n, b'status %d\n' % n)
        return self.send(404, b'unknown path\n')

    def body(self):
        if self.headers.get('Transfer-Encoding', '').lower() == 'chunked':
            data = b''
            while True:
                n = int(self.rfile.readline().strip().split(b';')[0], 16)
                if n == 0:
                    self.rfile.readline()
                    return data
                data += self.rfile.read(n)
                self.rfile.readline()
        return self.rfile.read(int(self.headers.get('Content-Length', 0)))

    def do_POST(self):
        if self.headers.get('Expect', '').lower() == '100-continue':
            pass   # BaseHTTPRequestHandler already answered it
        data = self.body()
        if self.path != '/echo':
            return self.send(404, b'unknown path\n')
        return self.send(200, b'%d %s\n' % (len(data), hashlib.sha256(data).hexdigest().encode()))

    do_PUT = do_POST


def serve(name, ctx, addr='127.0.0.1'):
    srv = http.server.ThreadingHTTPServer((addr, 0), H)
    if ctx is not None:
        srv.socket = ctx.wrap_socket(srv.socket, server_side=True)
    t = threading.Thread(target=srv.serve_forever, daemon=True)
    t.start()
    return '%s %d\n' % (name, srv.server_address[1])


def tls(kind):
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.minimum_version = ssl.TLSVersion.TLSv1_2
    ctx.load_cert_chain(os.path.join(CERTS, kind + '.crt'), os.path.join(CERTS, kind + '.key'))
    return ctx


lines = serve('http', None) + serve('https-ec', tls('ec')) + serve('https-rsa', tls('rsa'))
if BYNAME:
    lines += serve('http-byname', None, BYNAME)
with open(PORTFILE + '.tmp', 'w') as f:
    f.write(lines)
os.rename(PORTFILE + '.tmp', PORTFILE)
threading.Event().wait()
