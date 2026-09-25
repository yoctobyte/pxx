# CPython ORACLE for test/lib_mimic_urequests.npy -- not a library, and never
# imported by a pxx build. MicroPython's urequests semantics on top of CPython
# `requests`: no redirect following, one connection per request
# (Connection: close, as MicroPython sends). The lib-test row puts this
# directory on PYTHONPATH and runs the SAME test file under python3, then
# diffs the two transcripts. It skips when `requests` is not installed.
import requests as _r


def request(method, url, **kw):
    h = dict(kw.pop("headers", None) or {})
    h["Connection"] = "close"
    return _r.request(method, url, headers=h, allow_redirects=False, **kw)


def get(url, **kw): return request("GET", url, **kw)
def post(url, **kw): return request("POST", url, **kw)
def put(url, **kw): return request("PUT", url, **kw)
def patch(url, **kw): return request("PATCH", url, **kw)
def delete(url, **kw): return request("DELETE", url, **kw)
def head(url, **kw): return request("HEAD", url, **kw)
