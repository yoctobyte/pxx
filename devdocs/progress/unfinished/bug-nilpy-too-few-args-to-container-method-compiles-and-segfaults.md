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

## 2026-08-01 — PARTIALLY fixed; two framing corrections; the COMMON case remains

Measured on a self-hosted binary at `2a2b478e6` + the change below. Landing the
covered half because it turns real crashes into diagnostics, but the ticket
stays open: the shape people actually write is still broken.

### Correction 1: too MANY arguments is NOT rejected either

The ticket's contrast — "an arity check exists and only fails in one
direction" — is a measurement artifact. It compared `"a,b".split(",",1,2,3)` (a
**str** method, own validating table) against a **container** method. Measured
directly:

| call | result |
| --- | --- |
| `[1,2,3].index(1,2,3,4)` | SIGSEGV (not "rejected") |
| `[1,2,3].count(1,2,3)` | SIGSEGV |
| `{'a':1}.get(1,2,3,4)` | SIGSEGV |

So container methods have **no arity check in either direction**. Only str
methods validate. Do not build on the "one direction" framing.

### Correction 2: it is not container-specific — user classes crash too

```python
class C:
    def m(self, a):
        return 99      # never reads `a`
c = C()
print(c.m())           # SIGSEGV
```

`return 99` never touches the parameter, so the crash is the CALL FRAME, not a
garbage read in the body. Any NilPy method call with wrong arity is affected,
not just pylib containers.

### Root cause

`FindUMethArity` **falls back to the plain first-name-match** when no overload
accepts the count (`symtab.inc`, last line of the function — deliberate, and
other callers rely on it). So every caller's `if k >= 0 then` test can never
reject, and the default-filling loops that follow only fill parameters that HAVE
defaults — a missing REQUIRED argument is simply left unfilled.

### Fixed here

Arity validated at the call site (not by tightening `FindUMethArity`, whose
fallback is relied on elsewhere), reusing `ProcArityMatches`, exempting
`*args`/`**kwargs`:

- `PyParseClassMethodCall` — receiver is a LITERAL or constructor call:
  `[1,2,3].index()`, `{'a':1}.get()`, `C().m()`. Now a clear compile error.
- `PyParseVariantMethod` — guarded on `hitCi >= 0` (statically-known class
  only). Genuinely dynamic dispatch and the dual-candidate arms are left alone
  on purpose: distinct candidate classes may legitimately take different
  counts, so a compile error there would reject valid programs.

### NOT fixed — and this is the common case

A **NAME receiver** still segfaults, which is how the code is normally written:

```python
xs = [1, 2, 3]
xs.index()          # STILL SIGSEGV
c = C(); c.m()      # STILL SIGSEGV
```

Measured: neither `PyParseClassMethodCall` nor `PyParseVariantMethod` is entered
for these (gdb breakpoints on both, never hit). `FindUMeth(ci=0, 'm')` IS
called, so the class is known — the call is resolved by the **shared Pascal
parser** (`compiler/parser.inc`, the `FindUMethArity` sites at ~3307 / 3363 /
3415 and the method-call routes near 4724 / 4812), not by the NilPy paths.

Note plain **Pascal** arity IS enforced there — `f.Bar(1)` against
`Bar(a, b: Integer)` errors with "Expected: ,". So the relaxation is specific to
NilPy mode (`PyExprMode`), and that is where to look next. **That is shared
Track A ground** (`parser.inc`), so it needs the sole-A guard, and it is why
this was not extended in the same pass.

### Next step

Start at `parser.inc`'s NilPy method-call route and find where the argument list
is parsed without checking the callee's parameter count — Pascal's own path
enforces it by parsing exactly `ParamCount` arguments, so the question is what
NilPy mode does instead. Measure which route builds the AN_CALL for `c.m()`
(a probe is more reliable here than a gdb condition — several `$_streq`
conditions misfired during this investigation).

### Also worth deciding

Compile error vs catchable runtime `TypeError`. CPython raises TypeError at RUN
time, and this repo deliberately moved missing-dunder and list+non-list from
compile errors to runtime TypeErrors for exactly that reason (b1f5b0e0b,
eeae1e4a3). The str-method table, by contrast, still compile-errors. This fix
follows the str-method precedent because a compile error is strictly better than
a segfault and far simpler — but the end state is arguably a runtime TypeError,
and that is a Track U call rather than something to settle in passing.
