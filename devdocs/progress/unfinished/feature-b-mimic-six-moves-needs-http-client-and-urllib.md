---
track: B
prio: 35
type: feature
blocked-by: [feature-b-mimic-urllib-request-over-the-rtl-http-stack, bug-n-from-import-of-a-submodule-with-an-as-rename-loses-the-module]
summary: "`six.moves` is now the largest module-shim row on the ladder (4 files: html5lib/__init__.py, _inputstream.py, html5parser.py, filters/sanitizer.py). It cannot be shimmed on its own — six.moves is a table of RE-EXPORTS of `http.client`, `urllib` and `urllib.parse`, so it needs those modules to exist. urllib.parse is pure string work and is the tractable half; http.client needs the HTTP client filed separately."
status: working
owner: frank3-fc
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

---

## Status 2026-08-18 (frank3-fc): the tractable half is blocked too — parked

Dispatched to do the `urllib_parse` half alone, on the reasoning in this ticket
that it is pure string work and unblocks `sanitizer.py` by itself. Measured
before writing it, against `pinned` v349 (`596799fd9c6e`), and the reasoning
does not survive contact:

**`sanitizer.py`'s import spelling does not work, whatever the shim contains.**

```python
from six.moves import urllib_parse as urlparse    # line 15
uri = urlparse.urlparse(val_unescaped)            # line 841
```

`from M import <module> as alias` followed by `alias.f()` is
`undefined variable (f)` —
[[bug-n-from-import-of-a-submodule-with-an-as-rename-loses-the-module]] (N,
p70). Without the rename it works; renaming a FUNCTION works; a top-level
`import M as alias` works. And it is NOT the shim mapping: two plain modules
reproduce it identically.

So `mimic_urllib_parse.py` would today unblock **zero files** — the same
measured test this campaign applies everywhere, and the same answer that got
`xml.dom` refused three times. Writing it now would produce a correct module
sitting behind a wall, and would make the ladder row disappear into a different
error without a file moving.

### Also learned while measuring, and worth keeping

A shim CAN re-export another module; the constraint is narrow and specific:

| inside a `mimic_` shim | result |
| --- | --- |
| `import mimic_other as name` (literal filename) | ✅ works |
| `import plainmodule as name` | ✅ works |
| `import other as name` (the shim's MAPPED name) | ❌ the name is lost |

So when this unparks, `mimic_six_moves.py` must re-export by the literal
`mimic_urllib_parse` filename, and that is a workaround to register in
`devdocs/dev/track-b-workarounds.md` against
[[bug-n-from-a-shim-import-a-class-loses-its-class-level-attributes]]'s family
— the platonic spelling is `import urllib.parse as urllib_parse`.

### What unparks it

The p70 above. Then: write `mimic_urllib_parse.py` (urlparse/urlsplit/urljoin/
quote/unquote/urlencode, differential-tested against CPython by value, the way
the five shims in [[feature-b-module-shims-for-the-html5lib-corpus]] are), add
`mimic_six_moves.py` re-exporting it, re-run the ladder, and report past-vs-onto.
The `http_client` half stays out of scope — that is
[[feature-b-mimic-urllib-request-over-the-rtl-http-stack]].
