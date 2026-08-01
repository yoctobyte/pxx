---
summary: "NilPy: calling a pylib CONTAINER method with too FEW arguments compiles and SEGFAULTS — xs.index(), d.get() both core-dump; too MANY args is correctly rejected"
type: bug
track: N
prio: 75
---

# Too few arguments to a container method compiles, then segfaults

- **Type:** bug (NilPy, CRASH — missing arity check) — **Track N**
- **Opened:** 2026-08-01. Generalised from
  [[bug-nilpy-dict-from-pairs-and-bytes-decode-segfault]], where `b.decode()`
  bound to `decode(encoding)` with an uninitialised parameter. That turned out
  not to be specific to `decode`.

## Measured (self-hosted binary at `b78988fe8`)

| call | expected | pxx |
| --- | --- | --- |
| `[1,2,3].index()` | `TypeError` (missing argument) | **SIGSEGV, core dumped** |
| `{"a":1}.get()` | `TypeError` | **SIGSEGV, core dumped** |
| `[1,2,3].count()` | `TypeError` | compiles, returns `3` (wrong, but no crash) |
| `"abc".find()` | `TypeError` | compile error — **correct** |
| `"a,b".split(",",1,2,3)` | `TypeError` | compile error — **correct** |

Two contrasts pin it down:

1. **Too MANY arguments is rejected; too FEW is not.** So an arity check exists
   and only fails in one direction.
2. **`str` methods are rejected; container methods are not.** `str` methods go
   through their own table (`PyParseStrMethod` and the str-method table in
   `compiler/pyparser.inc`), which validates. `TPyList`/`TPyDict`/`TPyBytes`
   methods resolve as ordinary Pascal method calls and evidently do not.

## Impact

Every pylib container method taking arguments is a latent crash if called bare,
and the failure mode is the worst kind: it COMPILES, so there is no diagnostic
pointing at the call site, and the crash address is inside pylib. A typo or a
half-finished edit (`d.get()` while reaching for `d.get(k)`) becomes a
core dump instead of a compile error.

`.count()` is the quietly worse case — no crash, just a wrong value from reading
an uninitialised parameter, which is this repo's expensive failure shape.

## Cause (to determine — do NOT guess)

Unknown. The `decode` instance was a Pascal `overload` set where the zero-arg
form did not exist and the call bound to the one-arg form regardless, leaving
the parameter uninitialised. Whether the general case is the same
overload-resolution path, or a missing arity check on the NilPy method-call
lowering, is NOT established. `.count()` returning a plausible value while
`.index()` crashes suggests the argument slot is simply left as garbage rather
than the call being rejected, but that is a hypothesis.

Start by comparing the lowering of `xs.index()` against `xs.index(2)` with
`PXXDBG=a.ir:<proc>` (wrap in a `def` — the module-level dump prints nothing),
and check whether `FindUMethArity` (`compiler/symtab.inc`) is consulted on this
path at all.

## Fix shape

Reject a call with fewer arguments than the resolved method's required
parameter count, as a compile error (this is a static arity question, unlike the
operand-type cases which must be runtime `TypeError`s to stay catchable).
`FindUMethArity` already exists and is the natural check.

Where a Python method genuinely has an optional argument, the pylib method needs
a real overload for the shorter form — as `TPyBytes.decode` now has. Audit the
container classes for others: any `overload` set whose shortest form still takes
a parameter Python treats as optional has this bug.

## Gate

`make test-nilpy` + self-host byte-identical, plus a `.npy` asserting a compile
error (or catchable TypeError, per whichever the fix chooses) for each of
`index()`, `get()`, `count()` called bare, and confirming the correct-arity
calls are unchanged.
