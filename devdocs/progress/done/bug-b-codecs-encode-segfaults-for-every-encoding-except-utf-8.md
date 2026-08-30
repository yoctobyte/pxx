---
track: B
prio: 65
type: bug
blocked-by: []
summary: "`codecs.encode(s, 'ascii')` and `codecs.encode(s, 'latin-1')` SEGFAULT (exit 139, core dumped) for every input including the empty string. Only 'utf-8' works. Both encodings are in the shim's own seeded registry and `lookup` finds them, so the crash is in the charmap encode path, not in resolution."
status: done
owner: frankB
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

That differential is phase 1 of
[[feature-b-sweep-mimic-shims-against-cpython]], and **this crash blocks its
encode half** — a differential that cannot run against half its subject will
test one direction and be reported green, which is how the `urllib.parse`
header came to claim a gate it did not have. Fix this first, or land the decode
half with the encode half named as absent in both the test docstring and the
Makefile comment. A green `MIMIC-CODECS OK` must not stand for "codecs works"
while `encode` is untested.

## 2026-08-30 (frankB) — FIXED. A hard cast of a Variant to a class reference.

### Root cause

`charmap_encode` answers a **tuple**, so `r.at(0)` arrives as a **Variant that
box-tags** the `TPyBytes` — not as the object. `encode` unwrapped it with

```pascal
encode := TPyBytes(r.at(0));      { both charmap arms }
```

which is a hard cast reinterpreting the **variant record's own bytes** as an
object pointer. The result is a garbage reference that faults on first use.

**That explains the one detail that made the ticket look like a table bug: the
empty string crashed too.** The bad pointer is produced *after* the encode loop,
so having nothing to encode never protected it. It also explains why utf-8 was
fine — `Utf8Encode_` returns its `TPyBytes` directly and never goes through a
tuple.

### Why decode never had it, which is what hid it

`decode` does `decode := r.at(0)` into an **AnsiString** result — an ordinary
variant conversion the compiler performs correctly. Only the object-typed arm
needed an explicit unwrap, and only the object-typed arm got a cast instead. The
two functions sit adjacent and look symmetric; the asymmetry is invisible at a
glance, which is why a reader comparing them would not have spotted it.

### Grepped for siblings before closing, per normalise-dont-special-case

Exactly **two** sites in the whole tree, both here (the ascii and latin-1 arms).
Every other unwrap in `lib/rtl` uses the correct `pyvarobj` form —
`base64.pas:39` is the same idiom for the same type. So this is a local slip,
not a pattern, and no other module needs auditing.

Fixed with a **named** `BytesOfVar` helper rather than two inlined `pyvarobj`
calls: two call sites that must agree is exactly how this drifted.

### The crash was hiding a CORRECT implementation

With the unwrap fixed, nothing else in the encode path needed changing. Every
arm matches CPython 3.12:

| | `''` | `'a'` | `'abc'` |
| --- | --- | --- | --- |
| utf-8 / ascii / latin-1 | `b''` | `b'a'` | `b'abc'` |

and every error policy is already right — `ascii`+`'\xe9'` raises
`UnicodeEncodeError` under `strict`, gives `b'?'` under `replace` and `b''`
under `ignore`; `latin-1` encodes `'\xe9'`→`b'\xe9'` and `'Ā'` raises;
mixed input gives `b'a?b'` / `b'ab'`. **9/9 encode cases and 9/9 policy cases
match.** The charmap logic was never wrong; one bad unwrap made all of it
unreachable.

### Gate

Per-case differential against CPython above, byte-for-byte, at pin v395. The
full `.npy` differential is phase 1 of
[[feature-b-sweep-mimic-shims-against-cpython]] and is now writable **in one
pass**, which was the reason for taking this ticket first. Note that the decode
side still diverges — [[bug-b-codecs-strict-decode-does-not-raise-on-invalid-utf-8]]
— so the differential cannot land green until that one closes too.

## Log
- 2026-08-30 — resolved, commit 3c5f5bf6e.
