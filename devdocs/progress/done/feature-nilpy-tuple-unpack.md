---
track: N
prio: 55
type: feature
---

# NilPy: sequence unpacking (`a, b = ...`, `for k, v in ...`)

Hangs off [[feature-nilpy-corpus-uforth]]. Characterised 2026-07-20:

```python
a, b = 1, 2        # error: undefined variable (a)
a, b = b, a        # same
for k, v in d.items():   # needs the same machinery
    ...
```

## Why this one first among the remaining gaps

It is the ENABLER for dict iteration. `TPyDict.keylist` and `vallist` exist
and `for k in d` works ([[feature-nilpy-dict]], for-in landed the same
session), but `.items()` is only useful once a two-name loop target parses —
so this unlocks the idiomatic form the corpus actually writes.

## Shape

- `a, b = x, y` — a simultaneous assignment, so the right-hand side must be
  evaluated into temps BEFORE any store, or `a, b = b, a` silently becomes
  `a = b; b = a`. That is the whole reason this is not just two assignments.
- `for k, v in <dict>.items():` — desugar to the counted loop for-in already
  builds, taking key and value from the two parallel arrays rather than
  materialising pairs. A real tuple type is NOT needed for the censused uses
  and should not be invented for them.
- A genuine `(a, b)` tuple VALUE is a separate, larger question — see the
  tuple half of [[feature-nilpy-bytes-and-slices]]'s note about
  `PyAnnTypeAt` still rejecting `Tuple[...]`.

## Also still missing, characterised at the same time (not this ticket)

- `@property` — only `@dataclass` is accepted as a decorator.
- list / dict / generator comprehensions.

Both are listed in the uforth umbrella's census; neither blocks as early as
unpacking does.

## Gate

`test-nilpy` green with a `.npy` case diffed against CPython (including the
swap, which is where a naive lowering breaks) + `--tier quick` + self-host
byte-identical + `make fpc-check`.

## Log
- 2026-07-20 — resolved, commit 527e658b.
