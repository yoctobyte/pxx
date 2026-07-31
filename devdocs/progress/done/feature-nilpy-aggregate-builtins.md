---
summary: "nilpy: map/filter over an arbitrary callable value"
type: feature
track: N
prio: 50
---

# nilpy: the aggregate builtins

- **Type:** feature (Nil-Python frontend, builtins) — **Track N**
- **Status:** done
- **Opened:** 2026-07-26 — probing songformatter under nilpy
  ([[feature-demo-songformatter-pxx-target]]). Follows the earlier
  `feature-nilpy-missing-builtins` (done) — these are the ones still absent.

## 2026-07-31 — mostly done

`sum` · `max` · `min` · `any` · `all` · `sorted` · `set` were all already
implemented (undocumented — no `undefined variable` for any of them, verified
against CPython, no code change needed). Regression added:
`test/test_nilpy_aggregate_builtins.npy`.

`type` was genuinely missing. Rather than a general type-object builtin
(comparable, printable as `<class 'X'>`, the 3-arg dynamic-class-creation
form — none of which any censused corpus needs), implemented the one shape
that's actually used: `type(x).__name__` recognized as a whole unit in
`ParseFactor` (parser.inc), lowered onto the class instance's existing RTTI
pair — `GenMakeRttiOfCall` + `GenMakeClassRefOp(.., 'ClassName', ..)`, the
same machinery `x.ClassName` already uses. `x` must be statically `tyClass`;
a scalar or a variant-boxed instance errors loudly (`type(x).__name__ needs x
to be a class instance`) rather than reading a nonexistent RTTI blob, which is
what happened on the first attempt (segfault on `type(5).__name__` with no
such check). Bare `type(x)` with no `.__name__` also errors loudly rather than
returning something plausible-but-wrong.

**Still open:**

- `map(f, xs)` / `filter(f, xs)` over an arbitrary callable value. `map`
  partially exists (works for `int`/`str`/`float` conversion only — the
  error message says as much); `filter` is entirely `undefined variable`.
  Both need a value-callable ABI to invoke an arbitrary `f`, which is exactly
  [[bug-nilpy-callable-value-abi-sorted-key-and-builtins]]'s bigger gap —
  fixing THAT ticket's "shape of a fix" (a fixed-ABI wrapper for a def/lambda
  used as a value) unblocks both `map`/`filter` here and `sorted(key=...)`
  there for free, per that ticket's own note. Not worth a narrower
  special-case: `map`/`filter` need the exact same wrapper `sorted` does.
- `list.sort(key=...)` — same blocker, same note.

## Gate

`make test-nilpy` green with a `.npy` case per builtin diffed against CPython, +
`--tier quick` + self-host byte-identical.

## Log
- 2026-07-31 — resolved, commit 2bbb344c8066be398cde61d386139db7347c3bf7.
