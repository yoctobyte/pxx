---
track: T
prio: 50
type: bug
status: backlog
blocked-by: []
owner: ""
found: 2026-08-30
found-by: frank-optimize, while taking feature-opt-o3-now-has-differential-coverage-and-it-should-be-standing
summary: "`--opts` defaults to `0,2`, and a batch run without it is written up as clean \"across pxx -O levels\" — which is true of what ran and false of what a reader takes from it. The aarch64 cross batch of 2026-08-30 (150 seeds, seed-start 300100, no --opts) was cited for months-scale confidence in a backend carrying ten -O3 gate sites, having never built -O3. The fix is that the run's own record must state the levels it compared, not that the next person remembers the flag."
---

# A csmith batch record does not say which `-O` levels it compared

## The instance

`devdocs/progress/backlog/feature-c-csmith-differential-fuzzing.md`, section
**D1**, records:

```
tools/csmith_fuzz.py --target aarch64 --iters 150 --seed-start 300100
```

> **136 ran clean across pxx `-O` levels, 14 skipped, no findings.**

`tools/csmith_fuzz.py:595` — `ap.add_argument("--opts", default="0,2", ...)`.
No `--opts` in that command, so the batch compared **`-O0` against `-O2`** and
never built `-O3`. At the time, `ir_codegen_aarch64.inc` carried **10** `-O3`
gate sites by `tools/check_o3_backend_parity.py`'s own count — every W1 slice
that had been ported. The one tier the batch could not see is the tier those
sites live in.

Nothing in the write-up is false. *"Across pxx `-O` levels"* is an accurate
description of a two-level comparison. It is what a reader takes from it that is
wrong, and the reader has no way to tell: **the command is quoted in full and
the missing information is a default, which is invisible by construction.**

## Why the fix is in the harness, not in anyone's discipline

The natural response is "pass `--opts 0,2,3` next time". That fails the same way
the next time, because the failure mode is not forgetting — it is that the
*record* of a run cannot be checked against what the run did. A reader auditing
D1 today has to know the default's value and its history to catch it.

Suggested shape, in the harness's own voice, which it already has for the oracle
(it prints `NO ORACLE for aarch64 (LP64) -- aarch64-linux-gnu-gcc: not
installed` and drops the bucket rather than reporting a comparison it did not
make — exactly the right instinct, applied to one axis and not this one):

- **Print the `-O` levels in the run header** as an explicit list, alongside the
  target and the oracle status, so a pasted header carries them.
- **Say what was NOT compared.** `MISCOMPILE_OPT: -O0 vs -O2 (-O3 NOT BUILT)` is
  the same construction as `PXX_SLOW: NOT CHECKED`.
- Optionally write the resolved arguments into the findings directory, so a
  batch with zero findings still leaves a record of its own configuration.

Whether `--opts` should default to `0,2,3` is a separate question and probably
not: changing it silently re-prices every existing run's cost. **The record is
the bug; the default is a design choice.**

## Related

- `feature-opt-o3-now-has-differential-coverage-and-it-should-be-standing` — the
  ticket this was found under. Its item 3 asks for cross-target `-O3` coverage;
  D1 looked like it had already delivered that.
- Same family as `bug-t-csmith-harness-reports-slow-as-a-timeout` and
  `bug-t-csmith-oracle-list-is-keyed-on-isa-when-its-own-doctrine-says-data-model`:
  the harness reporting a comparison in terms that outrun what it measured.

## Gate

T's own. This is a reporting change; no compiler behaviour is involved.
