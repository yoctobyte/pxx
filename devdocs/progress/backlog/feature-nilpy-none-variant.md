---
track: N
prio: 50
type: feature
---

# NilPy: `None` as a first-class variant value (VT_EMPTY)

Hangs off [[feature-nilpy-corpus-uforth]]. Filed 2026-07-19 while sizing
[[feature-nilpy-dict]].

## The gap

`None` works today only where it can be represented as a *sentinel*:

- `Optional[SomeClass] = None` -> nil pointer, and `x is None` is a pointer
  compare. Correct, and it covers most of uforth's 115 `is None` /
  `is not None` sites.
- `Optional[int] = None` -> 0. Documented caveat in `PyAnnTypeAt`: an
  `Optional[int]` whose legitimate value is 0 aliases the sentinel.

What does NOT work is `None` as a value flowing through an `Any` (variant):
`d.get(k)` on a missing key, a list slot holding None, a function returning
`Optional[Any]`. The runtime already HAS the representation — `VT_EMPTY = 0`
in `defs.inc`, "unassigned slot" — it is simply not wired to the language.

## Shape

- `None` in an expression position where the target is a variant -> a variant
  literal with tag `VT_EMPTY`.
- `x is None` / `x is not None` on a variant-typed x -> tag compare against
  `VT_EMPTY`, NOT the current payload compare (which would call a
  VT_EMPTY-tagged slot equal to integer 0 — a silent wrong answer, so this
  ordering matters: land the tag compare in the same change).
- Truthiness: `if x:` on a variant must treat VT_EMPTY as false.
- `print(None)` -> `None`, matching CPython.

## Why it is filed separately from dict

Dict v1 ([[feature-nilpy-dict]]) deliberately ships `.get(k, default)` (the
2-argument form) and the mapping core, whose semantics need no None. The
1-argument `.get(k)` on a MISSING key is exactly this ticket — and it is the
form uforth uses at ~20 of its 21 `.get` sites, so dict is not really
finished for the corpus until this lands. Sequence: dict core, then this,
then re-drive.

## Gate

`test-nilpy` green with a `.npy` case diffed against CPython + `--tier quick`
+ self-host byte-identical + `make fpc-check`.
