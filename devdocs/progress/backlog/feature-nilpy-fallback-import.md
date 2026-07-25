---
summary: "nilpy: fallback import (try/except ImportError) — soft-fail an unresolvable import, take the alternative"
type: feature
track: N
prio: 50
---

# nilpy: fallback import (`try/except ImportError`)

- **Type:** feature (Nil-Python frontend, import system) — **Track N**
- **Status:** backlog
- **Opened:** 2026-07-25 — songformatter planning session. Replaces the earlier
  `feature-nilpy-dotted-from-import` (Rene: don't impersonate reportlab; give
  nilpy the honest portability primitive instead). See
  [[frank2-songformatter-pxx-target]].

## Motivation

`try: import X … except ImportError: import Y` is the single most common
real-world Python **portability idiom** — every serious package uses it for
optional/alternative deps. Supporting it makes far more real-world Python compile
under nilpy (push generality down — [[frank2-mission-compile-real-world-asis]]),
and it is the honest mechanism for platform-split backends:

```python
try:
    from reportlab.pdfgen import canvas     # cpython: real reportlab
except ImportError:
    from pxxpdf import canvas                # nilpy: pxx pdfgen-backed compat lib
```

Under cpython the first import wins. Under nilpy `reportlab` is unresolvable, so
nilpy must **soft-fail that import and compile the `except` branch** — instead of
today's hard error. Consumer code downstream is identical (both bind `canvas`),
which is why [[feature-lib-pxxpdf-reportlab-compat]] mimics reportlab's API.

Rene also floated a short `import X if not import Y` form — decide whether to add
sugar or just support the `try/except ImportError` shape (the latter is standard
Python and preferred).

## Current walls

- `import` → `tkUses` at LEX time (`compiler/pylexer.inc:49`) — eager,
  branch-agnostic; no compile-time pruning, no `__nilpy__`/`sys.implementation`
  marker.
- `from X import …` accepted ONLY for dataclasses/typing/itertools; else hard
  error `'Nil Python: from-import of module … is not supported yet'`
  (`compiler/pyparser.inc:8761-8783`).
- Bare `import name` already resolves a sibling unit (`ParseUsesUnit`,
  `pyparser.inc:8799`) — so `import pxxpdf` (a sibling module) works once the
  fallback lets us reach it.

## Intended surface

1. Recognize `try: <import(s)> except ImportError: <import(s)>` at module scope.
2. Attempt the try-branch imports; on **unresolvable module** (not a runtime
   error — a compile-time resolution miss), discard that branch and compile the
   except-branch imports instead. No hard error for the skipped module.
3. Must PARSE (consume) a dotted `from a.b import c` in the try-branch even though
   it will be skipped under nilpy — do NOT need to RESOLVE `a.b` (we never load
   reportlab). Parsing-to-skip only.
4. Bind the names from whichever branch was taken.

## Acceptance

- A test: `try: from nonexistent.pkg import thing except ImportError: from
  realmod import thing` compiles under nilpy, binds `thing` from `realmod`, runs.
- The reportlab→pxxpdf fallback compiles (verified by
  [[feature-lib-pxxpdf-reportlab-compat]]).
- Existing `make test-nilpy` green + self-host byte-identical.
- Under cpython the same source still prefers the try-branch (semantics unchanged
  there — it's real Python).

## Consider (Track U, not here)

A `sys.implementation.name == 'nilpy'` marker would enable an explicit
`if nilpy:` split as an alternative to try/except. Out of scope; file a `decide-*`
if wanted (try/except is the standard idiom and covers the need).

## Log
- 2026-07-25 — filed, replacing feature-nilpy-dotted-from-import.
