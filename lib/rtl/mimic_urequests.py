# SPDX-License-Identifier: 0BSD
"""mimic_urequests -- MicroPython's `urequests`: a small HTTP client.

    import urequests
    r = urequests.get("http://127.0.0.1/data")
    print(r.status_code, r.text)
    d = r.json()
    r = urequests.post(url, json={"a": 1})

`import urequests` resolves here through the NilPy import resolver's `mimic_`
fallback. It is written in Python over the `socket` shim (mimic_socket.pas),
which has a POSIX backend and an lwIP one, so the same program runs on a
desktop and on an ESP32. That is also how MicroPython's own urequests is built:
Python over usocket.

THE NAMES are MicroPython's, which are a subset of CPython `requests`:
request(method, url, data=None, json=None, headers=None, timeout=None) and
get/post/put/patch/delete/head(url, ...). The Response has status_code,
reason, headers (a dict, keys as the server spelled them), content (bytes),
text, encoding, json() and close(). test/lib_mimic_urequests.npy runs the same
file under CPython `requests` against the same server and diffs the output.

ONE DELIBERATE DIFFERENCE FROM MICROPYTHON: the body is read in full and the
socket is closed before request() returns. MicroPython keeps the socket open
until .content is read or close() is called, so a caller that only checks
status_code leaks a socket per request. On an ESP32 that is one of about ten
lwIP sockets, so it runs out quickly. close() is kept, and it is harmless.

WHAT IT REFUSES, LOUDLY:
  * https:// raises ValueError. The TLS backends are http.pas's, a caller
    picks one, and this module has no way to take that choice.
  * a host name other than a dotted quad or 'localhost'. The socket shim has
    no resolver and says so (OSError), so no guess is made here.
  * a redirect is NOT followed; the 3xx response comes back as it is, with its
    Location header. This matches MicroPython's urequests, not CPython
    requests.

HTTP/1.0 with `Connection: close`, as MicroPython sends, so no chunked
transfer encoding can come back. The body ends at Content-Length when the
server sends one, and at close otherwise.
"""
import socket
import json as _json


class Response:
    def __init__(self, status_code, reason, headers, content):
        self.status_code = status_code
        self.reason = reason
        self.headers = headers
        self.content = content
        self.encoding = "utf-8"

    @property
    def text(self):
        return self.content.decode(self.encoding)

    def json(self):
        return _json.loads(self.content.decode(self.encoding))

    def close(self):
        pass


def _split_url(url):
    # -> (host, port, path). Only http:// is spoken.
    if url.startswith("https://"):
        raise ValueError("urequests: https is not supported (no TLS backend in this client)")
    if not url.startswith("http://"):
        raise ValueError("urequests: unsupported URL scheme: " + url)
    rest = url[7:]
    cut = rest.find("/")
    if cut < 0:
        hostport = rest
        path = "/"
    else:
        hostport = rest[:cut]
        path = rest[cut:]
    port = 80
    colon = hostport.find(":")
    if colon >= 0:
        host = hostport[:colon]
        port = int(hostport[colon + 1:])
    else:
        host = hostport
    return host, port, path


def _read_head(s):
    # Reads up to the blank line; returns (head_text, body_bytes_already_read).
    got = b""
    while True:
        cut = got.find(b"\r\n\r\n")
        if cut >= 0:
            return got[:cut].decode(), got[cut + 4:]
        chunk = s.recv(512)
        if not chunk:
            return got.decode(), b""
        got = got + chunk


def request(method, url, data=None, json=None, headers=None, timeout=None):
    host, port, path = _split_url(url)
    body = b""
    ctype = ""
    if json is not None:
        body = _json.dumps(json).encode()
        ctype = "application/json"
    elif data is not None:
        if isinstance(data, str):
            body = data.encode()
        else:
            body = data
    req = method + " " + path + " HTTP/1.0\r\nHost: " + host
    if port != 80:
        req = req + ":" + str(port)
    req = req + "\r\n"
    have_ctype = False
    if headers is not None:
        for k in headers:
            if k.lower() == "content-type":
                have_ctype = True
            req = req + k + ": " + headers[k] + "\r\n"
    if ctype != "" and not have_ctype:
        req = req + "Content-Type: " + ctype + "\r\n"
    if len(body) > 0 or method == "POST" or method == "PUT" or method == "PATCH":
        req = req + "Content-Length: " + str(len(body)) + "\r\n"
    req = req + "Connection: close\r\n\r\n"

    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    try:
        if timeout is not None:
            s.settimeout(timeout)
        s.connect((host, port))
        s.sendall(req.encode() + body)
        head, content = _read_head(s)
        lines = head.split("\r\n")
        status = lines[0].split(" ", 2)
        if len(status) < 2 or not status[0].startswith("HTTP/"):
            raise ValueError("urequests: not an HTTP response: " + lines[0])
        code = int(status[1])
        reason = ""
        if len(status) > 2:
            reason = status[2]
        hdrs = {}
        length = -1
        i = 1
        while i < len(lines):
            line = lines[i]
            colon = line.find(":")
            if colon > 0:
                name = line[:colon]
                value = line[colon + 1:].strip()
                hdrs[name] = value
                if name.lower() == "content-length":
                    length = int(value)
            i = i + 1
        if method != "HEAD":
            while length < 0 or len(content) < length:
                chunk = s.recv(1024)
                if not chunk:
                    break
                content = content + chunk
            if length >= 0 and len(content) > length:
                content = content[:length]
        else:
            content = b""
    finally:
        s.close()
    return Response(code, reason, hdrs, content)


def head(url, **kw):
    return request("HEAD", url, **kw)


def get(url, **kw):
    return request("GET", url, **kw)


def post(url, **kw):
    return request("POST", url, **kw)


def put(url, **kw):
    return request("PUT", url, **kw)


def patch(url, **kw):
    return request("PATCH", url, **kw)


def delete(url, **kw):
    return request("DELETE", url, **kw)
