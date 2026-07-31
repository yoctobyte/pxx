---
track: N
prio: 35
type: feature
blocked-by: []
---

# set methods missing: issubset/issuperset/union/intersection/difference/discard

Found by proactive CPython-diff sweeping, right after landing the set
OPERATOR forms (`&`/`|`/`-`/`^`, see
`bug-nilpy-set-and-dict-operators-do-raw-pointer-arithmetic`) — the
equivalent NAMED methods (`s.union(t)` etc.) didn't exist at all
(`TPyList has no method issubset`). `.add()` already existed (the dedup
insert every set literal uses) and `.remove()` already existed (shared with
`list.remove`), but the rest of the set method surface was missing.

## Fix

Added ordinary `TPyList` instance methods (`compiler/builtin/pylib.pas`) — no
parser wiring needed, since these resolve through the normal
class-method-call path like any other method:
- `issubset`/`issuperset` — linear scan via the existing `pycontains`
  membership helper.
- `union`/`intersection`/`difference` — thin wrappers over the operator
  implementations already added for `|`/`&`/`-` (`pyset_or`/`pyset_and`/
  `pyset_sub`).
- `discard` — like `remove()` but does not raise when the value is absent
  (checks `pycontains` first).

Verified against CPython (values only — a set still displays with list
brackets, the separate tracked cosmetic gap, so the regression test uses
`sorted(...)` around the container-returning methods to check computed
values without depending on that unrelated display difference). Regression
test `test/test_nilpy_set_methods.npy` gated in `test-nilpy`. Self-host
confirmed byte-identical (pylib.pas is a runtime unit, no compiler rebuild
needed, but `make pxx-debug` run anyway per this session's habit).

## Log
- 2026-07-31 — resolved, commit HEAD.
