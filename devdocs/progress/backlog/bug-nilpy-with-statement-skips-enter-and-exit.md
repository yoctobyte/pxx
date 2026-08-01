---
summary: "NilPy: `with Ctx() as x:` runs the body but SILENTLY SKIPS __enter__ and __exit__ — setup never happens and cleanup never runs, with no error"
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

## Note on the names

`__enter__` and `__exit__` **do** appear in `compiler/**` (unlike `__bool__`,
`__abs__`, `__and__` and the other never-referenced dunders found in the same
sweep). So this is not simply an unimplemented protocol — some handling exists
and does not fire for a plain user class. **Find out what the existing
references do before writing new code**; a partially-wired path is a different
fix from an absent one, and the same caution applied to the reflected arithmetic
dunders in [[feature-nilpy-arithmetic-dunders-full-protocol]].

Plausible: `with` is wired only for pylib's own file objects (the
`open(...) as f` case, which is what the corpus actually uses) and a user class
falls through to "just run the body". Verify with `PXXDBG` (`a.ast:<proc>` /
`a.ir:<proc>`) rather than assuming.

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
