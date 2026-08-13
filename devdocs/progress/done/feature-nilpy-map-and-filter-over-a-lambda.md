---
track: N
prio: 40
type: feature
status: done
owner: claude-A-N
---

# `map(lambda ...)` is unimplemented and `filter` does not exist

```python
list(map(lambda v: v + 1, [1, 2]))
# error: Nil Python: map() over lambda is not implemented (int, str and float are)

list(filter(lambda v: v > 1, [1, 2, 3]))
# error: undefined variable (filter)
```

`map` exists but only with a TYPE as the first argument (`map(int, ...)`);
`filter` is absent entirely. Both fail at compile time, so nothing computes a
wrong answer — filed as a feature.

The callable-value machinery this needs is already in place: a lambda in a
name, a lambda in a list, and a lambda passed to a `Callable[...]` parameter
all work today, and `sorted` already works. So this is wiring two builtins to
the existing runtime dispatcher rather than new infrastructure. `sorted(key=)`
and `min`/`max` with a `key=` are the same shape and worth doing in the same
pass.

Found by the functions/closures sweep against CPython.

## Mostly already fixed — verified 2026-07-31; ONE gate case still segfaults

`map`/`filter` over a lambda AND a named def, each consumed by `list()` and
by a `for` loop, already landed (via `pymap_call`/`pyfilter_call` in
pyeval.pas, reached from ordinary compiled code, not just `exec()`) and all
match CPython exactly — re-measured directly, not assumed.

The ticket's own third gate case does NOT work: `map(c.double, xs)` (a
BOUND METHOD as the callable) SEGFAULTS. Root cause: `pymap_call`/
`pyfilter_call`'s `key` parameter is typed `Pointer` (8 bytes) — a bound
method is a `{code, receiver}` PAIR (16 bytes), so passing one through
truncates the receiver half. This is the SAME representation gap as
[[bug-nilpy-bound-method-cannot-pass-through-a-callable-parameter]]
(already investigated and deferred this session as needing a careful,
multi-call-site pass through `PyAnnTypeAt`'s parameter-vs-field typing) —
not a separate bug, just another call site hitting the identical limit.
Left OPEN rather than closed: fixing the shared representation issue fixes
both at once, so this ticket stays a live pointer to that gap rather than
being marked done on the strength of 2 out of 3 shapes.

Added `test/test_nilpy_map_filter_lambda_def.npy` covering the WORKING
shapes (lambda, def, both via `list()` and `for`) so they have direct
regression coverage; the bound-method crash is NOT asserted there (it
would turn a segfault into a test-harness crash) — it stays reproducible
via this ticket's own repro until the representation fix lands.

## Gate

`make test-nilpy` + self-host byte-identical, plus `map`/`filter` over a
lambda, a named def and a bound method, each consumed by `list()` and by a
`for` loop.

## DONE 2026-08-13 — the third gate shape works now; closing

The one case left open above — `map(c.double, xs)` with a BOUND METHOD as the
callable — no longer segfaults. The shared representation gap it was waiting on
([[bug-nilpy-bound-method-cannot-pass-through-a-callable-parameter]]) has since
been closed, and this call site went with it, which is exactly why the ticket
was left as a live pointer rather than closed at 2 out of 3.

Re-measured, not assumed: all three callables (lambda, named def, bound method)
x both consumers (`list()` and a `for` loop) x both builtins — twelve rows,
every one matching CPython. `sorted(key=)`, `min(key=)` and `max(key=)` over a
lambda match too.

`test/test_nilpy_map_filter_lambda_def.npy` gains the four bound-method rows it
deliberately omitted, with the note about why they were absent replaced by why
they are now there. The receiver carries state (`self.k`) on purpose: a
truncated receiver — the original failure — would still compute something for a
stateless method.

Gate: self-host fixedpoint + `gate.sh quick` GREEN.

## Log
- 2026-08-13 — resolved, commit PENDING-COMMIT.
