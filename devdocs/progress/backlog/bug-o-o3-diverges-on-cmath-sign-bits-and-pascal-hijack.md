---
summary: "optdiff finds -O3 changing observable behaviour in two C tests — cmath_sign_bits returns rc 42 against the baseline's rc 1, and cmath_no_pascal_hijack's output differs at equal rc"
type: bug
track: O
prio: 65
---

# `-O3` diverges from the baseline on two cmath tests

- **Type:** bug (Track O — optimization; file-owned by Track A per CLAUDE.md)
- **Found:** 2026-08-09 by the Track T watcher on plexus, opt tier, sha
  `dcfe7a6f8f0f`. Filed by Track T per "T owns the tool, never the bug".

## What optdiff reports

```
OPT DIFF -O3: test/cmath_no_pascal_hijack.c (rc 0 vs 0)
OPT DIFF -O3: test/cmath_sign_bits.c        (rc 42 vs 1)
optdiff shard 1/12: pass=102 skip=16 diff=2
```

A real run: wall 563.6s, `compiler_sha256 9d511d465b6f`, 102 passing beside
the two diffs.

**`cmath_sign_bits` is the sharp one.** Same program, same source, different
**exit code** — 42 optimized against 1 unoptimized. An `-O3` pass is changing
observable behaviour, not just code shape. `cmath_no_pascal_hijack` differs in
OUTPUT at equal rc, which is the same class one step quieter.

Sign-bit handling is exactly where this hurts: a wrong `-0.0`, a comparison
folded on the assumption that `x == -x` implies zero, or a `copysign`
strength-reduced past its sign semantics all produce a plausible wrong value
rather than a crash — the failure mode `devdocs/dev/debugging-playbook.md`
calls the expensive one.

## Repro

```
tools/testmgr.py --tier opt --job 'optdiff#shard1/12'
```

or directly, which is what optdiff does per program: build at the baseline
level and at `-O3`, run both, compare rc and stdout.

## Why this sat unticketed

Track T's own fault, now fixed. The stub-filing dedupe (`81cc6cadb`) keyed on
test SOURCE, and every optdiff shard carries `tools/optdiff.sh` as its src —
the driver, not the program — so one already-ticketed shard silenced the rest.
Fixed in `5b7b3691d`: dedupe now requires the targets to differ. A second flaw
found alongside it — the dedupe was matching a ticket in `done/` — is fixed
too. Neither changes anything about the findings below; they are real.

## Note on scope

Two diffs in one shard, both cmath, both sign/format adjacent — likely ONE
cause rather than two. Worth diffing the emitted code for `cmath_sign_bits`
between `-O2` and `-O3` first and identifying which pass is responsible, before
treating them separately.

## Gate

`tools/testmgr.py --tier opt` with `optdiff#shard1/12` clean, and no new diffs
in the other eleven shards.
