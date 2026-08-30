---
track: B
prio: 65
type: bug
blocked-by: []
summary: "`codecs.encode(s, 'ascii')` and `codecs.encode(s, 'latin-1')` SEGFAULT (exit 139, core dumped) for every input including the empty string. Only 'utf-8' works. Both encodings are in the shim's own seeded registry and `lookup` finds them, so the crash is in the charmap encode path, not in resolution."
status: backlog
owner: unassigned
---

# `codecs.encode` segfaults for every encoding except utf-8

- **Type:** bug (library) — **Track B** (`lib/rtl/mimic_codecs.pas`).
- **Filed:** 2026-08-30 by frankB during the `mimic_` shim differential sweep
  (`feature-b-sweep-mimic-shims-against-cpython`).
- Measured against **pin v395** (`aa78a7faf63a`). A crash, so this is an
  ordinary prio bug, not a compat nicety.

## Repro — two lines

```python
import codecs
print(repr(codecs.encode('abc', 'ascii')))
```

```
Segmentation fault (core dumped)
EXIT=139
```

The program **compiles clean** (`ok: ... procs=2173`); the crash is at run time.

## The boundary, measured

| input | `utf-8` | `ascii` | `latin-1` |
| --- | --- | --- | --- |
| `''` | `b''` | **SEGV** | **SEGV** |
| `'a'` | `b'a'` | **SEGV** | **SEGV** |
| `'abc'` | `b'abc'` | **SEGV** | **SEGV** |

So it is not input-dependent and not a high-codepoint edge — the **empty
string** crashes too. It is the encoding that selects the broken path, and
`utf-8` is the only one that survives, presumably because it has a dedicated
`Utf8Encode_` route rather than going through the charmap.

## What is NOT the cause

- **Not registry lookup.** `codecs.lookup('ascii')` and `lookup('latin-1')`
  both succeed and report the right `.name`; `lookup('no-such-codec')` correctly
  raises `LookupError`.
- **Not `charmap_build`.** `codecs.charmap_build('abc')` returns and prints
  `built ok`, exit 0.

Which points at `charmap_encode` or the encoding-table construction it is handed
(`AsciiTable` / `Latin1Table` at `mimic_codecs.pas:386,394`) rather than at the
dispatch above them.

## Note on how this was nearly missed

The first probe of this shim wrapped each call in a `lambda` for a table-driven
loop. That returned `None` for the bytes-valued cases and produced a *plausible
wrong story* — "encode returns None for every encoding" — with no crash visible
at all, because the lambda never delivered the value that would have crashed on
use. The lambda itself is a separate frontend bug
([[bug-n-a-lambda-returning-a-captured-heap-value-yields-none]]). Re-probing
with `def` produced the segfault immediately.

Recorded because it is the failure mode the debugging playbook warns about: the
instrument was broken, and the broken instrument returned something believable.
**Use `def`, not `lambda`, in NilPy probes until that ticket closes.**

## Gate

A `.npy` differential over `encode`/`decode` × `utf-8`/`ascii`/`latin-1` ×
`strict`/`replace`/`ignore`, diffed byte-for-byte against CPython — the shape
`test/lib_mimic_urllib_parse.npy` uses. `mimic_codecs.pas` has **no differential
at all** today, which is why a total crash in two of its three encodings was
sitting in a 574-line module unnoticed.
