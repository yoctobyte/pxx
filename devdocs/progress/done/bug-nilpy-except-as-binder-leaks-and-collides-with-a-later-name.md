---
prio: 55
track: N
type: bug
blocked-by: []
status: done
---

# An `except ... as e` binder leaks and collides with a later ordinary `e`

- **Type:** bug (NilPy; valid CPython → SIGSEGV) — **Track N**
- **Found:** 2026-08-09, realistic-program sweep (a shop inventory that catches
  `except ValueError as e` in its sell loop and then walks the stock with
  `e = STOCK[item]`).

```python
STOCK = {"a": {"count": 1}}

try:
    raise ValueError("boom")
except ValueError as e:
    print("caught", e)

for k in sorted(STOCK):
    e = STOCK[k]           # CPython: fine — the binder was deleted
    print("B", k, e["count"])      # pxx: SIGSEGV
```

`e` is an utterly ordinary name to reuse for a table entry, and nothing in the
program hints at the connection — the crash is in the second loop, the cause is
a handler thirty lines up.

## Cause

`PyParseTry` did `handlerVar := AllocVar(handlerName, tyClass)` under the
**user's own spelling**. That second symbol then won for every later reference,
so the later assignment stored a dict into an exception-typed slot and reading
it back dereferenced the wrong layout.

Python does not work that way: the binder is scoped to the handler and is
**deleted when the handler ends** — reading `e` afterwards is a NameError. So
there was never a value to leak in the first place.

## Fix

Bind a HIDDEN name and re-spell the references inside the handler's own suite,
exactly the treatment a comprehension's loop variable already gets
(`PyRenameIdentRange`). The hidden name is derived from the suite's INDENT token
INDEX and nothing else, so a trial parse that renames and a real parse that
renames again compute the same name and the second pass is a no-op — the
comprehension names are idempotent for the same reason.

`PyRenameIdentRange` lives further down the include than `PyParseTry`, so it
needed a `forward` — the FPC seed canary is what caught that, not the self-host
(pxx resolves it either way).

## Verified

`test/test_nilpy_except_as_binder_scope.npy` — the collision, a plain
reassignment of the binder name, two handlers reusing one name, nested handlers
where the inner shadows the outer's spelling, and the same shapes inside a def.
Diffs clean against `.expected`, which is CPython's own output.
`make compiler/pascal26` fixedpoint + `tools/gate.sh quick` GREEN (FPC seed
canary included).

Not fixed here, and hit by the same program: a user-raised `KeyError(k)`'s
`str()` loses CPython's repr quotes. That is the documented `e.args` gap,
[[bug-nilpy-exception-str-and-repr-diverge-from-cpython]], and the test steps
around it deliberately.

## Log
- 2026-08-09 — resolved, commit d1e78c768.
