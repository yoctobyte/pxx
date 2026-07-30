---
track: N
prio: 55
type: bug
---

# A METHOD returning a freshly built string leaks it; the same def does not

A method whose result is a managed string leaks roughly 32 bytes per call
when the returned value is FRESH (a literal, a `str(...)`, a concatenation).
Returning a FIELD — a borrow — is flat, and a plain top-level `def` returning
the same fresh string is flat too. So the divergence is method-vs-def, not
string-vs-object.

## Measured (RSS slope, 20k vs 320k calls)

| body of `label(self) -> str` | 20k | 320k |
| --- | --- | --- |
| `return "lit"` | 0.94 MB | **10.3 MB** |
| `return str(self.v)` | 0.94 MB | **10.3 MB** |
| `return self.k` (field, a borrow) | 0.30 MB | 0.30 MB — flat |
| same body as a plain `def label(k, v) -> str` | 0.30 MB | 0.30 MB — flat |

Driver holds ONE receiver outside the loop and calls `len(x.label())`, so the
receiver's own lifetime is not in the measurement.

## First measurement — the two bodies' IR, side by side

Same program, `return "lit"` in both:

```
Node.label                              flabel
0: zero_sym  a=264            tk=23     (none)
1: const_str a=41 b=3         tk=4      0: const_str a=53 b=3   tk=4
2: store_sym a=264 b=1        tk=4      1: store_sym a=263 b=0  tk=4
```

tk=23 is `tyAnsiString` (managed), tk=4 is `tyString` (frozen). The method's
`$pyresult` is a MANAGED slot — it gets the prologue `zero_sym` — and the
frozen literal is then stored into it with a raw `store_sym`, not through the
ARC assign path. The def's `$pyresult` gets no `zero_sym` at all, i.e. the two
paths do not agree on the result slot's storage class. That disagreement, not
the literal, is the thing to chase.

## Where to look

The method body path allocates `$pyresult` in a different place from the def
path (pyparser.inc: the method arm uses `Procs[procIdx].RetType`, the def arm
uses the header's `retType`), and the two differ in how a managed result is
retained/released. Diff the two allocation sites first, and dump the emitted
IR of both bodies (`PXXDBG=a.ir:Node.label` vs `PXXDBG=a.ir:label`) before
theorising — the def version is the known-good oracle here, which is what
makes this cheap to localise.

Found while measuring
[[bug-nilpy-object-reclamation-disabled-inside-py-modules]]; independent of it
(reproduces on the main-program path with the pre-fix compiler).

## Gate

`make test-nilpy` + self-host byte-identical, plus the table above going flat.

## Log
- 2026-07-30 — resolved, commit c13328cb5.
