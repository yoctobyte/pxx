---
track: B
prio: 35
type: feature
blocked-by: [feature-b-mimic-urllib-request-over-the-rtl-http-stack, bug-n-from-import-with-an-as-rename-loses-what-it-renames]
summary: "`six.moves` is now the largest module-shim row on the ladder (4 files: html5lib/__init__.py, _inputstream.py, html5parser.py, filters/sanitizer.py). It cannot be shimmed on its own — six.moves is a table of RE-EXPORTS of `http.client`, `urllib` and `urllib.parse`, so it needs those modules to exist. urllib.parse is pure string work and is the tractable half; http.client needs the HTTP client filed separately."
status: done
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
[[bug-n-from-import-with-an-as-rename-loses-what-it-renames]] (N,
p75). Without the rename it works and a top-level `import M as alias` works.
(This ticket first said "renaming a FUNCTION works" — wrong, and corrected in
the bug: a renamed function loses its signature, so a zero-argument call
SEGFAULTS and an omitted default is dropped. The one-argument case I first
measured is the shape that happens to survive.) And it is NOT the shim mapping: two plain modules
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

---

## LANDED 2026-08-18 (frank3-fc) — the urllib_parse half, on pinned v351

The blocker ([[bug-n-from-import-with-an-as-rename-loses-what-it-renames]]) was
fixed and reached Track B in v351, so the park is over. `mimic_urllib_parse.py`
and `mimic_six_moves.py` are in, `make lib-test` green.

**The park was the right call and this is the evidence:** the shim's CONTENTS
were never the blocker. Written now, in the same shape it would have had two
hours ago, it moves five files. Written then, it would have moved none.

### Verified by value, through the corpus's own spelling

`test/lib_mimic_six_moves.npy` reaches urllib.parse the way
`html5lib/filters/sanitizer.py` does — `from six.moves import urllib_parse as
urlparse`, a RENAMED re-export through two shims — because testing
`urllib.parse` directly would pass without exercising that path, and that path
is the one that did not work before v351. 27 checks, identical under CPython.

The cases are the sanitizer's own, not generic ones: the scheme is lower-cased
(a lower-case allow-list otherwise lets `JavaScript:` through — a security
difference, not a cosmetic one), `data:` keeps its semicolon while `http:`
splits `;params` off (the sanitizer reads `uri.path` to check a `data:` content
type), and an unbalanced `[` raises ValueError (the sanitizer catches exactly
that and DELETES the attribute).

### Score: past the wall 0, onto the next wall 5

`missing module: six_moves` 5 → 0.

| file | now |
| --- | --- |
| `html5lib/__init__.py` | undefined variable (yield) |
| `_inputstream.py` | undefined variable (yield) |
| `_tokenizer.py` | undefined variable (yield) |
| `html5parser.py` | undefined variable (yield) |
| `filters/sanitizer.py` | **unexpected token** — see below |

compile **6/48 → 6/48**. `yield` is now **18 files**, and this ticket put four
of them there.

**Attribution:** the row cleared because this shim exists — before it, those
files stopped at `missing module: six_moves`. But `sanitizer.py` also needed
frank2's rename fix to get past `urllib_parse as urlparse`, so that file is a
joint result and not this ticket's alone.

### The one file this ticket existed for moved one step, onto a new wall

`sanitizer.py:769` is `super(Filter, self).__init__(source)` — the
two-argument `super`, which does not parse:
[[bug-n-two-argument-super-does-not-parse]] (N, p60). html5lib writes it in
every filter, so it is not one file's habit.

### Still out of scope, unchanged

The `http_client` half. `_inputstream.py` imports it and would stop there if
`yield` were fixed; `lib/rtl/http.pas` exists and needs a Python face —
[[feature-b-mimic-urllib-request-over-the-rtl-http-stack]].

### One workaround taken

`ParseResult.__getitem__` binds its field tuple to a local before indexing,
because subscripting a container literal inside a function body segfaults
([[bug-n-subscripting-a-container-literal-inside-a-function-segfaults]], N,
p65, found here). Registered in `devdocs/dev/track-b-workarounds.md` with its
revert condition.

## Log
- 2026-08-18 — resolved, commit 53ccaa4da.
