# CPython ORACLE for test/lib_mimic_urequests.npy -- not a library, and never
# imported by a pxx build. MicroPython's urequests semantics on top of CPython
# `requests`: no redirect following, one connection per request
# (Connection: close, as MicroPython sends). The lib-test row puts this
# directory on PYTHONPATH and runs the SAME test file under python3, then
# diffs the two transcripts. It skips when `requests` is not installed.
import requests as _r
import warnings as _w

# https:// without verification, because MicroPython's urequests wraps with
# ssl.wrap_socket(s, server_hostname=host), whose default is CERT_NONE.
# urllib3 warns about exactly that on stderr, which the transcript captures.
_w.filterwarnings("ignore", message="Unverified HTTPS request")


def request(method, url, **kw):
    h = dict(kw.pop("headers", None) or {})
    h["Connection"] = "close"
    if url.startswith("https://"):
        kw.setdefault("verify", False)
    return _r.request(method, url, headers=h, allow_redirects=False, **kw)


def get(url, **kw): return request("GET", url, **kw)
def post(url, **kw): return request("POST", url, **kw)
def put(url, **kw): return request("PUT", url, **kw)
def patch(url, **kw): return request("PATCH", url, **kw)
def delete(url, **kw): return request("DELETE", url, **kw)
def head(url, **kw): return request("HEAD", url, **kw)
