---
summary: "nilpy: sum/max/min/any/all/sorted/set/map/filter/type builtins"
type: feature
track: N
prio: 50
---

# nilpy: the aggregate builtins

- **Type:** feature (Nil-Python frontend, builtins) — **Track N**
- **Status:** backlog
- **Opened:** 2026-07-26 — probing songformatter under nilpy
  ([[feature-demo-songformatter-pxx-target]]). Follows the earlier
  `feature-nilpy-missing-builtins` (done) — these are the ones still absent.

## Missing (each `undefined variable`)

`sum` · `max` · `min` · `any` · `all` · `sorted` · `set` · `map` · `filter` ·
`type` (songformatter uses `type(exc).__name__`)

`len`, `str`, `int`, `range`, `enumerate`, `zip`, `list` already work.

## Notes

- `sorted(xs, key=..., reverse=...)` and `list.sort(key=...)` need a callable
  value, so the `key=` form waits on [[feature-nilpy-lambda]]; the plain forms
  don't and are worth having first. `list.sort(key=lambda ...)` currently fails
  with `undefined variable (key)`.
- `any`/`all` over a generator expression additionally needs
  [[feature-nilpy-generator-expression-arg]]; over a list they don't.
- `set` needs a set type: membership, `add`, `len`, iteration in sorted order for
  determinism. songformatter uses sets for note collections.

## Gate

`make test-nilpy` green with a `.npy` case per builtin diffed against CPython, +
`--tier quick` + self-host byte-identical.
