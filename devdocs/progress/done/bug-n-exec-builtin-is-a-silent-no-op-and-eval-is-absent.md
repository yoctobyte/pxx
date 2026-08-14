---
track: N
prio: 55
type: bug
summary: "`exec(s, d, d)` compiles, runs, and does NOTHING — the target dict is left empty where CPython has the bound name. A program using it runs and is silently wrong. `eval(s)` is absent entirely (loud, so much less dangerous). Both should map onto the already-shipped feature-lib-pyexec, which does the real work today."
status: done
owner: agent-AN
---

# `exec()` builtin is a silent no-op; `eval()` is missing

- **Type:** bug (silent wrong behaviour) — **Track N**.
  Measured by Track T on 2026-08-14 while closing
  [[decide-nilpy-eval-at-runtime]] with the user.

## Measured

```python
d = {}
exec("x = 1 + 2", d, d)
print(sorted(d.keys()))
```

| | pxx | CPython |
| --- | --- | --- |
| the above | **`[]`** | `['__builtins__', 'x']` |
| `eval("1+2")` | `error: undefined variable (eval)` | `3` |
| `exec("x = 1")` then `print(x)` | compile error | `1` |

## The no-op is the dangerous half

`eval` being absent is a **compile error** — loud, immediate, and it names
itself. `exec` is worse: it accepts the call, returns, and binds nothing, so a
program that relies on it runs to completion producing wrong results. That is
the failure mode this repo has paid the most for, and it is exactly what the
NilPy upward-compatibility rule exists to prevent — *code that works on CPython
must work on NilPy*.

## The existing test cannot catch it

`test/test_nilpy_exec_stub.npy`:

```python
d = {}
d["k"] = 5
exec("x = 1", d, d)
print(d["k"])        # <- asserts the PRE-EXISTING key, never "x"
```

It checks that `exec` does not crash and that it does not clobber the dict. It
never checks that `exec` did anything. So the suite is green on a no-op, and has
been.

## The capability already exists — this is wiring, not building

[[feature-lib-pyexec]] is **done**: exec-as-a-library in CPython's explicit-dict
form, no ambient scope capture, host-supplied name -> value bindings including
bound methods of compiled classes (it is how uforth's PYTHON blocks call into
their VM), diffed against `python3`. `compiler/builtin/pyeval.pas` is 5289
lines and there is a compile-time evaluator besides.

So the fix is to route the builtin names onto that, not to write an interpreter.
The user's standing policy, recorded on the decide ticket: where a construct
cannot be settled at compile time, falling back to the runtime library is
legitimate — slower than compiled, correct, with full run-time type information.

Scope worth deciding while implementing rather than after: the library form is
**explicit-dict only**. Ambient-scope `exec("x = 1")` that writes into the
caller's locals is a different and much harder thing in a compiled dialect, and
may belong in `nilpy-semantics-divergences.md` rather than in the fix.

## Gate

The three rows above match CPython. And `test_nilpy_exec_stub.npy` is rewritten
to assert the key `exec` was supposed to define — as written it would pass
against a no-op, which is how this survived.

## Settled 2026-08-14 (user): they are BUILTINS, auto-included — do not ask again

> *"In Python we don't really have some runtime library in that sense. Everything
> is already part of the Python RTL — it's sort of auto-included in every Python
> application as soon as we need it."*

So there is no "expose it as a builtin, or require an import?" question to
resolve while implementing. `eval` and `exec` are **language builtins**, pulled
in on demand like the rest of the NilPy RTL, exactly as CPython presents them.
A program must not have to import anything to use them.

That also settles the naming: the user-visible names are `eval` and `exec`. The
`pyexec` library stays the mechanism underneath; it is not the interface.

## Resolution

The ticket said this was wiring, not building, and it was — but the wiring was
not where it looked. `exec` was **already** routed to `EvalPyStmts` in
`parser.inc` (not to pylib's `pyexec` stub, which is dead for this path). The
no-op was one level down: `EvalPyStmts` ran the statements correctly and then
threw the bindings away.

Its locals live in pyeval's own `LclNames`/`LclVals` arrays, and the `l`
argument was accepted for API compatibility and otherwise ignored — the one
exception being a hand-wired line that published `__body__` back for uforth's
`exec(...)` / `ns["__body__"]()` idiom. That single special case WAS the general
answer, waiting to be generalised.

### What changed

- **Flush.** Every top-level binding is written into `l` on the way out — the
  `__body__` line generalised. This is frame-correct without doing anything
  about frames: `CallUserFn` saves and restores the whole local frame around a
  call, so when control returns `LclN` holds exactly the top-level names, which
  is precisely what CPython puts in `l`. A function body's locals were never in
  that frame to leak.
- **Read.** A new `EnvL` is consulted on a name MISS, between the locals arrays
  and the globals dict — Python's order. So a pre-existing entry in `l` is
  visible to the exec'd source, not merely preserved.
- **`eval`.** `EvalPyExpr` (var-out) plus a thin `pyeval_expr` function wrapper,
  and an `eval` arm in `parser.inc`. Trailing tokens are refused, so
  `eval("x = 1")` is an error as in CPython rather than half-evaluated.

### The design call inside it — NOT seeding

The obvious implementation is to copy `l` into the locals arrays at entry and
copy back at exit. **Rejected on cost, deliberately.** `LclFind` is a LINEAR
scan, so seeding an N-entry namespace makes every name lookup in the exec'd
source O(N). uforth calls `exec` in a hot loop against a namespace that grows
across a run, and it is already the subject of an open slowness ticket — so
that is a real cost, not a hypothetical one. The miss-time fallback is one dict
`indexof` instead, and gives the same visibility.

### Measured — the ticket's three rows

| | before | after | CPython |
| --- | --- | --- | --- |
| `exec("x = 1 + 2", d, d)` then `sorted(d.keys())` | `[]` | `['x']` | `['__builtins__', 'x']` |
| `eval("1+2")` | `undefined variable (eval)` | `3` | `3` |
| `exec("x = 1")` then `print(x)` | `expected ,` | a named refusal (below) | `1` |

Row 1's residual is the `__builtins__` key — CPython injects the builtins
MODULE and NilPy has no module object to put there. Escalated rather than
guessed: [[decide-nilpy-exec-injects-a-builtins-key]], with the row recorded in
`nilpy-semantics-divergences.md`. Reading `d["x"]` agrees; only enumerating the
namespace can see it.

Row 3 is the ambient form the ticket flagged as "worth deciding while
implementing". It stays unsupported — the caller's locals are compiled stack
slots with no run-time name table — but it is now refused BY NAME, at compile
time, with the working spelling in the message, instead of failing as
`expected ,` on the closing paren. `eval` needs no such restriction: an
expression only reads, so an invisible name is a run-time error naming itself,
never a silent wrong value.

### The test that could not catch it

`test/test_nilpy_exec_stub.npy` rewritten as the ticket demanded. It asserted a
PRE-EXISTING key, so it was green against a no-op and had been for as long as
`exec` was one. It now asserts the binding `exec` was supposed to make, plus
visibility of a pre-existing binding, multi-statement sequences, rebinding, and
`eval` — **byte-identical to CPython**, and the Makefile expectation went from
`"5"` to all six lines.

Gate: `gate.sh quick` GREEN (self-host fixedpoint + `--tier quick` + FPC seed
canary), before and after the pin.

**Pinned (v305).** `pyeval.pas` is the runtime of a compiled `.npy` PROGRAM, not
a unit the compiler links, so this was NOT a gate requirement
([[project_builtin_change_needs_repin_for_gate_fixedpoint]], corrected scope) —
the gate was green unpinned. It is pinned because otherwise the fix does not
reach programs built with `$(PXX_STABLE)`, which would leave `exec` a no-op for
every Track B/E consumer while the suite said it worked. The frozen builtin set
is unchanged (8 files, `pyeval.pas` modified), so the dangling-source trap that
recurred with `exceptions.pas` does not apply — checked, not assumed.

### Not verified here

uforth is `EvalPyStmts`'s heaviest user and its tree is **not on this box**
(`~/projects/uforth` absent), so `make test-uforth` skips. The change is
additive for it — a flush of top-level names it does not read, and a read
fallback that can only turn a NameError into a value — but Track T's matrix
against this sha is what actually covers it.

## Log
- 2026-08-14 — resolved, commit 000ad05dd.
