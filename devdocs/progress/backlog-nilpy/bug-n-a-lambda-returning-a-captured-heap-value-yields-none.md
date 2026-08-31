---
track: N
prio: 60
type: bug
blocked-by: []
summary: "A lambda whose body is a captured heap-typed value returns None: `lv = [1]; (lambda: lv)()` is None, not [1]. Holds for list, dict, tuple and bytes; str and int are fine, a literal body is fine, a parameter passthrough is fine, and a nested `def` with the identical body is fine. Silent wrong VALUE in ordinary Python, and it makes lambda-based test probes lie."
status: backlog
owner: unassigned
---

# A lambda returning a captured heap value yields `None`

- **Type:** bug — **Track N** (Nil-Python frontend).
- **Filed:** 2026-08-30 by frankB, found when it corrupted a shim probe during
  the `mimic_` differential sweep.
- Measured against **pin v395** (`aa78a7faf63a`). CPython runs every line below
  and prints the value; we print `None`.

## Repro — three lines

```python
lv = [1]
f = lambda: lv
print(repr(f()))          # pxx: None      CPython: [1]
```

## The boundary, measured

| body | pxx v395 | CPython |
| --- | --- | --- |
| `lambda: [1]` — list **literal** | `[1]` | `[1]` |
| `lambda: lv` — list **variable** | **`None`** | `[1]` |
| `lambda: {'k':1}` literal | `{'k': 1}` | same |
| `lambda: dv` dict variable | **`None`** | `{'k': 1}` |
| `lambda: (1,)` literal | `(1,)` | same |
| `lambda: tv` tuple variable | **`None`** | `(1,)` |
| `lambda: b'a'` literal | `b'a'` | same |
| `lambda: bv` bytes variable | **`None`** | `b'a'` |
| `lambda: sv` **str** variable | `'a'` | `'a'` |
| `lambda: iv` **int** variable | `1` | `1` |
| `lambda x: x` — parameter passthrough, list arg | `[1]` | `[1]` |
| `lambda: bv + b'x'` — expression over captured bytes | **`None`** | `b'ax'` |
| `lambda: len(lv)` — captured value **consumed** | `2` | `2` |
| nested `def` returning the same captured `lv` | `[1, 2]` | `[1, 2]` |

Three facts pin it:

1. **It is the RETURN that is lost, not the capture.** `len(lv)` inside the
   lambda is correct, so the captured object is reachable and intact; only
   handing it back as the lambda's value produces `None`.
2. **It is lambda-specific.** A nested `def` with a byte-identical body works,
   so this is not closure machinery in general.
3. **It is heap-typed values only.** `str` and `int` survive; list, dict, tuple
   and bytes do not. A literal body survives, which suggests the literal is
   materialised in the lambda's own frame while a captured reference is not
   retained across the return.

Local *and* global captures both fail, so it is not about which scope the name
comes from.

## Why prio 60 despite Track N being deprioritised

Not a missing feature and not a diagnostic — a **wrong value, silently**, for a
shape that is ordinary Python: `key=lambda p: (p.a, p.b)`, `lambda: []` as a
default factory, `lambda: cached_dict`. Nothing raises and nothing warns; the
`None` propagates to whatever consumes it.

It also **makes measuring instruments lie**, which is how it was found. A
table-driven probe of `mimic_codecs` wrapped each call in a `lambda`, and the
bytes-valued rows came back `None` — a plausible, self-consistent, entirely
wrong story ("`codecs.encode` returns None for every encoding"). Re-probing with
`def` showed the truth: `encode` is fine for utf-8 and **segfaults** for ascii
and latin-1 ([[bug-b-codecs-encode-segfaults-for-every-encoding-except-utf-8]]).
A broken instrument that returns something believable is the exact failure the
debugging playbook is organised against, so the blast radius here includes every
future lambda-based probe.

**Until this closes: use `def`, not `lambda`, in NilPy probes.**

## Note for whoever takes it

`sorted(..., key=lambda p: (p[0], p[1]))` currently gives the RIGHT answer,
because the tuple is consumed by the sort rather than returned to Python — case
13 above. So a naive "does sorting still work?" check will pass and is not
evidence the bug is absent. Test by *returning* the value.
