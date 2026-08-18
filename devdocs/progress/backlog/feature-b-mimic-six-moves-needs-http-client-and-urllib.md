---
track: B
prio: 35
type: feature
blocked-by: [feature-b-mimic-urllib-request-over-the-rtl-http-stack]
summary: "`six.moves` is now the largest module-shim row on the ladder (4 files: html5lib/__init__.py, _inputstream.py, html5parser.py, filters/sanitizer.py). It cannot be shimmed on its own — six.moves is a table of RE-EXPORTS of `http.client`, `urllib` and `urllib.parse`, so it needs those modules to exist. urllib.parse is pure string work and is the tractable half; http.client needs the HTTP client filed separately."
---

# `six.moves` needs `http.client` and `urllib` to exist first

- **Type:** feature (library) — **Track B**.
- **Filed:** 2026-08-18 by frank3-fc from
  [[feature-b-module-shims-for-the-html5lib-corpus]], where it was measured and
  deliberately not written.

## Why it is not a shim you can just write

`six.moves` exists to give one name to a module that moved between Python 2 and
3. Every member is a re-export, so `mimic_six_moves.py` cannot *contain*
anything — it can only forward to modules this build does not have.
`lib/rtl/mimic_six.py` already says so in its DELIBERATELY ABSENT note; this
ticket is that note ranked as work.

## What the corpus actually imports

```
html5lib/_inputstream.py     from six.moves import http_client, urllib
html5lib/filters/sanitizer.py  from six.moves import urllib_parse as urlparse
```

plus two files that inherit the wall transitively (`html5lib/__init__.py`,
`html5parser.py`), which is why the row counts 4.

## The two halves, and they are not equally hard

- **`urllib_parse`** — `urlparse`, `urljoin`, `quote`, `unquote`,
  `urlencode`. Pure string manipulation against a published grammar (RFC 3986):
  writable exactly, testable as a differential against CPython, no backend.
  **This is the tractable half and it unblocks `sanitizer.py` on its own.**
- **`http_client`** — needs a real HTTP client, which is
  [[feature-b-mimic-urllib-request-over-the-rtl-http-stack]]. `_inputstream.py`
  imports it to fetch a document by URL.

Doing the first half alone is worth it and does not commit to the second.
Note `_inputstream.py` imports both in one statement, so it stays blocked until
`http_client` exists regardless.

## Caveat carried from the parent ticket

`_inputstream.py` and `html5parser.py` currently stop on `six_moves` FIRST and
have `CodecInfo` behind them. Do not read this row's 4 files as 4 files
unblocked; measure with `tools/nilpy_ladder.py` after, as the parent did.
