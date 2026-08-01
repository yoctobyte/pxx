---
summary: "NilPy: `with` is desugared to a plain assignment — the context-manager protocol is deliberately not modelled, so a user __enter__/__exit__ silently never runs"
type: bug
track: N
prio: 70
---

# `with` skips `__enter__`/`__exit__` entirely

- **Type:** bug (NilPy semantics, silent) — **Track N**
- **Opened:** 2026-08-01, from the CPython differential sweep (1094 cases,
  self-hosted binary at `3f2c5b915`).

## Measured

```python
class Ctx:
    def __enter__(self):
        print("enter")
        return self
    def __exit__(self, a, b, c):
        print("exit")
        return False

with Ctx() as x:
    print("body")
```

CPython: `enter` / `body` / `exit`.
pxx: **`body`** — and nothing else.

Both dunders are skipped. The body runs, so the program looks like it worked.

## Why this is high priority despite `with` being "just sugar"

The whole point of `with` is that cleanup is guaranteed. Silently skipping
`__exit__` means:

- files/sockets/locks are never released — and the failure appears far from the
  cause, as exhaustion or corruption much later
- `__enter__`'s return value is not what `as x` binds, so `x` is whatever the
  expression evaluated to rather than what the context manager chose to expose
  (these can legitimately differ — that is what `__enter__` returning something
  other than `self` is for)
- an exception inside the body never reaches `__exit__`, so suppression
  (`return True`) and rollback semantics are silently absent

No diagnostic at any point. This is the repo's expensive-bug shape — plausible
behaviour, wrong far from the cause.

## Cause — a DELIBERATE simplification, now outgrown (corrected 2026-08-01)

The ticket first guessed this was a partially-wired path, because `__enter__`
and `__exit__` appear in `compiler/**` while `__bool__`/`__abs__`/`__and__` do
not. **That guess was wrong.** The only occurrence is a comment, and it states
the design decision outright (`compiler/pyparser.inc`, above `PyParseWith`):

> `with EXPR as VAR:` — desugared to `VAR = EXPR` followed by the body. The
> context-manager protocol (`__enter__`/`__exit__`) is not modelled: the only
> censused use is `with open(...) as f`, and pyopen reads the whole file
> eagerly, so there is nothing to close.

So `PyParseWith` lowers `with E as v:` to exactly `v = E` plus the body. The
reasoning was sound for the corpus it was written against — but it makes `as v`
bind the **expression** rather than `__enter__`'s return value, and it silently
does nothing for any user-defined context manager.

This is therefore a feature gap with a documented rationale, not a regression.
What makes it worth a bug ticket rather than a feature request is that it fails
**silently**: a class that defines the protocol compiles clean and its setup and
teardown simply never run.

## Scope to check when fixing

- `__enter__`'s return value binds to the `as` target (not the expression).
- `__exit__` runs on the exception path too, receiving the exception triple, and
  a truthy return SUPPRESSES the exception.
- `__exit__` runs on `break`/`return` out of the body.
- Nested and multi-item `with` (`with A() as a, B() as b:`) unwind in reverse.
- A class missing one of the two dunders should raise a genuine runtime
  `TypeError`, not silently run the body.

## Gate

`make test-nilpy` + self-host byte-identical, plus a `.npy` diffed against
CPython covering each bullet above — in particular the exception path and the
suppressing `__exit__`, which a happy-path test would miss. Keep whatever
existing `open(...) as f` behaviour the corpus relies on green.

## Fix shape (concrete, given the cause above)

`PyParseWith` (`compiler/pyparser.inc`) currently builds `v = E; body`. It needs
to build, for a context manager whose class declares the protocol:

```
__cm = E
v    = __cm.__enter__()
try:
    body
except:                       # any exception
    if not __cm.__exit__(type, value, tb):  raise
else / finally:
    __cm.__exit__(None, None, None)
```

NilPy already has real `try`/`except` lowering
(`project_nilpy_exceptions_landed`), so this is composition of existing pieces
rather than new machinery. The exception triple is the awkward part — check what
the existing `except` lowering can hand over before designing the signature; a
first cut may pass `None, None, None` on the exception path too and note the
divergence, rather than block on it.

Keep the current fast path for a class that declares NEITHER dunder, so
`with open(...) as f` and every other existing use stay byte-identical — that is
what makes this landable incrementally.

**Static receivers only**, like the other dunder dispatches: a context manager
arriving as an untyped parameter is a variant and needs
[[decide-nilpy-runtime-dunder-dispatch-mechanism]]. Say so in the test rather
than leaving a red case.

## FIXED 2026-08-01 — protocol runs; suppression deliberately deferred

`PyParseWith` (`compiler/pyparser.inc`) now lowers, when the expression's class
declares `__enter__` or `__exit__`:

```
__py_cm_N = EXPR                  { hidden temp — __exit__ must run on the SAME
                                    object, and the `as` target may be rebound }
v         = __py_cm_N.__enter__()
try:
    body
finally:
    __py_cm_N.__exit__(None, None, None)
```

- `as v` binds **`__enter__`'s return value**, not the expression. The test
  proves this with a manager returning something other than `self` — the only
  shape that can distinguish the two.
- `try`/`finally` (`AN_TRY_FINALLY`, the node Pascal already lowers) so
  `__exit__` runs on the exception path and on `break`/`return` out of the body.
- Gated on the class actually declaring a dunder, so `with open(...) as f` and
  every other existing use keep the old plain-assignment desugar byte for byte.
  Asserted in the test.
- `PyCallMeth3` added beside `PyCallMeth2` for the four-parameter `__exit__`.

Verified against CPython, byte-identical: `as` binding, the exception path
(`__exit__` runs, then the exception propagates and is caught outside), nesting
unwinding in reverse, a bare `with` with no `as`, and `with open(...)`.

Native confirm: FPC seed build clean, self-host fixedpoint A==B==C from the
pinned seed, testmgr --tier quick GREEN.

### NOT done, and deliberately not faked: `__exit__` suppression

CPython lets a truthy `__exit__` SWALLOW the exception. `try/finally` cannot
express that — it needs the exception triple handed to `__exit__` and a
conditional re-raise. Consequences of the current shape, both recorded in the
test file:

- a truthy `__exit__` does **not** suppress; the exception still propagates.
- `__exit__` receives `None, None, None` even on the exception path.

Every non-suppressing manager (`__exit__` returning `None`/`False` — the
overwhelming majority) is exactly right. Faking suppression would silently
swallow errors, which is strictly worse than not supporting it, so it stays
open as a follow-up rather than being half-implemented.

Multi-item `with A() as a, B() as b:` is also untested — check whether it parses
at all before assuming it works.
