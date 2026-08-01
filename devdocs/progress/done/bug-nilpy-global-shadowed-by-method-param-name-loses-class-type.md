---
summary: "NilPy: a module-level variable whose NAME matches any method parameter loses its class type at operator-dispatch sites — every dunder silently stops dispatching, while attribute access on the same variable still works"
type: bug
track: N
prio: 75
---

# A global sharing a name with a method parameter loses its class type (operators only)

- **Type:** bug (NilPy type inference / scoping, silent) — **Track N**
- **Opened:** 2026-08-01. Found while writing a regression test for
  [[bug-nilpy-bitwise-shift-on-class-operand-segfaults]] — the test failed for a
  reason unrelated to the fix it was testing, which is how this surfaced.
- **Pre-existing, NOT a regression:** reproduced on
  `stable_linux_amd64/default/pinned` (v239), which predates all of
  2026-08-01's changes.

## Repro

```python
class V:
    def __init__(self, n):
        self.n = n
    def __add__(self, other):        # parameter named `other`
        return "ADD" + str(other.n)

other = V(1)                          # module-level variable, SAME name
p = V(2)
print(other.n)                        # CPython 1      pxx 1       OK
print(other + p)                      # CPython ADD2   pxx TypeError: expected a number, got object
```

Rename **either** side — the global to `w`, or the parameter to `zz` — and it
works (`ADD2`). Nothing else changes.

## What makes it sharp

In the *same program*, the *same variable* is typed correctly for one
construct and wrongly for another:

| use of `other` | result |
| --- | --- |
| `other.n` (attribute access) | `1` — correct, so the variable IS known to be a `V` |
| `other + p` (operator dispatch) | `TypeError` — dispatch never fires |

So this is not "the global lost its type" wholesale. The **operator dispatch
site reads a different type source than the member-access site**, and that
source is what the parameter clobbers. Any fix has to identify which of the two
is authoritative rather than patch the symptom.

Not name-specific: verified with `o`, `other` and `zz` — any collision does it.
Method parameters and plain-function parameters both trigger it.

## Impact

`def __add__(self, other)` / `def __eq__(self, other)` is the idiomatic Python
spelling, and `other`, `o`, `value`, `item`, `key`, `n` are all ordinary global
names too. A collision is easy to hit by accident, and the failure is either a
`TypeError` far from the cause or — worse — a silent fall-through to handle
arithmetic wherever the operand pair does not happen to raise.

It also silently disables every compile-time dunder dispatch landed on
2026-08-01 (ordering, `__ne__`, bitwise/shift, truthiness) for any program with
such a collision, because all of them key on the operand's static class.

## Cause (to determine — do NOT guess)

Unknown. The likely shape is the NilPy local-typing pre-pass
(`project_nilpy_ast_typing_and_string_kind_widen` — locals are typed by a trial
AST parse) writing the parameter's type onto a symbol the module-level variable
also resolves to, with member access reading the class from a different field
that survives.

**Measure first**: `PXXDBG=n.locals` prints nothing for module scope, so start
by making it do so, or hoist the repro into a function to get a dump. Compare
`ASTTk`/`ResolveNodeRec` at the two use sites. Do not conclude from the
description above — the repo's history of wrong root causes is exactly this
shape of plausible story.

## Gate

`make test-nilpy` + self-host byte-identical, plus a `.npy` diffed against
CPython covering: global-vs-method-param collision, global-vs-plain-function-param
collision, attribute access and operator dispatch on the same variable, and a
non-colliding control. Add it near the dunder tests, whose own regression tests
must avoid the collision until this is fixed (noted in
`test/test_nilpy_dunder_bitwise.npy`).

## 2026-08-01 — narrowed substantially, and the original framing corrected

Not fixed. What follows is measured; the corrections matter because the first
write-up would have sent a fix to the wrong place.

### Correction 1: dunder dispatch is NOT broken

The ticket said "no dunder dispatches at all". Wrong — dispatch fires fine:

```python
def __add__(self, o):
    return 99          # -> 99, correct, even with a global named `o`
    return o.n         # -> TypeError: expected a number, got object
```

So the operator resolves and the method is entered. Only reading the shadowed
NAME misbehaves.

### Correction 2: the method body is byte-for-byte fine

`PXXDBG=a.ir:V.__add__` for the broken (param `o`) and working (param `other`)
versions produces **identical IR** — same ops, same shape. The defect is not in
the method.

### Where it actually is: the global is a VARIANT

Dumping the call site (`PXXDBG=a.ir:call`) shows the receiver passed as a
boxed variant while the non-shadowed operand is a plain class:

```
1: lea       a=293 ... tk=17 [sym=o]     <- shadowed global: lea + arg tk=22 (variant)
4: load_sym  a=294 ... tk=6  [sym=p]     <- unshadowed global: tyClass
```

So the module-level `o` really is typed `tyVariant`, and `o.n` then goes
through a numeric variant path — which is the `expected a number, got object`.
Attribute access "working" earlier was the variant unbox coping, not evidence
the type was right.

### The module constraint table is NOT the cause (for the method-param case)

`PXXDBG=n.locals` now prints the module table (see below). For the
method-param repro it is **correct**: `<module> o tk=6 rec=0`. So the table
says tyClass while the emitted symbol is a variant — meaning the global symbol
was allocated as a variant BEFORE the constraint could apply, and the
allocation is what to chase, not the table.

For the *function-local* variant of this bug (`def f(): zz = "hello"` poisoning
a module-level `zz`) the table IS wrong — `<module> zz tk=22` — widened by the
function local's `tyString`. So there are plausibly **two** paths into the same
symptom; do not assume one fix covers both, and re-check the other repro after
fixing either.

### Tooling landed with this investigation

`PyDbgDumpLocals` was already called per-PROC but never for the module table,
so `PXXDBG=n.locals` printed nothing for module-scope names. Now wired
(`compiler/pyparser.inc`), which is how the two paragraphs above were measured.

### Rejected fix, do not retry as-is

Skipping non-`skGlobal` symbols in `PyCollectModuleLocalsAST`'s harvest loop.
Measured ineffective: the def-body symbols are allocated with `CurProc < 0` and
so are ALREADY `skGlobal` (`harvest zz kind=1 tk=23`). Reverted rather than
landed. The discriminator has to be lexical (the scan already tracks
`blockIsDef[depth]`), not the symbol kind.

## 2026-08-01 (later) — FIXED. Root cause was neither table; the earlier theory was wrong

The param-collision path is fixed and verified byte-identical to CPython. The
cause is in a THIRD place — not the module constraint table and not the
`PyCollectModuleLocalsAST` harvest, both of which the notes above (correctly)
cleared but then pointed at the wrong successor.

### Where it actually was: `PyAllocModuleGlobals`

`PyAllocModuleGlobals` pre-creates a module global as a bare `tyVariant` when a
def declared ABOVE it reads it — the `def refresh(): bpm_label.set(...)` at the
top, `bpm_label = tk.StringVar(...)` at the bottom shape. Its "does a def above
read this name" scan matched **any `tkIdent` token equal to the name inside a
def body**, with no notion of what that name is BOUND to there. A parameter of
the same name is precisely such a token, so

    def __add__(self, other):   # `other` here is the PARAMETER
        return "ADD" + str(other.n)
    ...
    other = V(1)                # module global, pre-created tyVariant

pre-created the global as a variant BEFORE its own assignment ran. The
assignment then found `symIdx >= 0` and took the branch that skips the type
decision entirely, so the correct `tyClass` RHS never applied.

The fix: a parameter SHADOWS a module global for the whole body (Python
scoping — and unlike a plain local assignment, no `global nm` can take a
parameter back), so its uses are not reads of the global. New
`PyDefHeaderBindsName` answers "does this def header bind nm as a parameter",
and the scan carries a `shadowStack` parallel to the existing `inDefStack`
(nested defs inherit the shadow). Name POSITIONS only: `def f(x: int)` and
`def f(x = other)` are an annotation and an enclosing-scope default, so both
still read as genuine uses.

### Corrections to the notes above — both were measurement artifacts

- **"the module constraint table is correct here"** — true, and it stays true
  after the fix; it was never consulted, because the `if symIdx < 0` guard had
  already been skipped. The table was a red herring in BOTH directions.
- **"the global symbol was allocated as a variant BEFORE the constraint could
  apply, and the allocation is what to chase"** — right instinct, wrong
  allocator. It is not the seeding loop: a probe on that loop's skip branch
  never fired once. It is `PyAllocModuleGlobals`.
- **`PXXDBG=n.locals` showing `<module> o tk=6`** dumps `PyLocals`. That is
  genuinely correct and genuinely irrelevant — reading it as "so the table is
  not the cause, therefore the symbol must have been pre-allocated by the
  typing pre-pass" skipped the pass that actually did it.

How it was finally pinned, after two hypotheses died to measurement: a
temporary trace in `AllocVar` filtered to the one name, then a **gdb conditional
breakpoint** (`break AllocVar if $_streq(name, "other")`, `bt`) on the `-g`
build. The backtrace named `PyAllocModuleGlobals` in one step. That is the
playbook's own lesson again — three rounds of plausible reasoning cost more
than one backtrace.

### Regression test

`test/test_nilpy_global_shadowed_by_param.npy`, wired into `make test-nilpy`,
expectation = CPython's own output. Covers method-param collision (`__add__`,
`__eq__`), plain-function-param collision, attribute access AND operator
dispatch on the same shadowed variable, annotation/default non-collisions, and
a non-colliding control. Confirmed RED on the pre-fix binary (`TypeError:
expected a number, got object`) and GREEN after.

### Still open — split out, NOT covered by this fix

Re-checked after fixing, as the note above asked:

- `def f(): zz = "hello"` poisoning a module-level `zz` is **still broken**, and
  there the module table really is wrong (`<module> zz tk=22`). Different pass,
  different mechanism → filed as
  [[bug-nilpy-def-local-assignment-widens-module-global-to-variant]].
- Rebinding a module global from a scalar to a class (`other = 0` … `other =
  V(1)`) loses dunder dispatch with **no collision involved at all** → filed as
  [[bug-nilpy-module-global-rebound-scalar-then-class-loses-dispatch]].

## Log
- 2026-08-01 — resolved, commit PENDING.
