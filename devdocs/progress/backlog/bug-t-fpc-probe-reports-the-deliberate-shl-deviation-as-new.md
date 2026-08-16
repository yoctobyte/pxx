---
track: T
prio: 25
type: bug
blocked-by: []
summary: "`tools/fpc_diff_probe.sh` reports `shl-shr-neg` as a NEW divergence on every run, but that row is the DELIBERATE native-width shift decision of 2026-08-11. A permanent false NEW trains the reader to skim the one line that is supposed to mean something."
---

# The FPC probe reports the deliberate `shl` deviation as a new divergence

Measured 2026-08-16 (a Track A+C+P+N session ran the probe while bughunting):

```
DIFF        shl-shr-neg   fpc=[2147483644|-16]  pxx=[9223372036854775804|-16]
---
new divergences: 1   known/filed: 16
```

That is not a bug in the compiler. `shl`/`shr` compute at NATIVE width and
never truncate as of 2026-08-11 — a deliberate dialect decision, with four rows
that differ from FPC on purpose (see the shift note in the dialect docs and
`project_shifts_happen_at_native_width_since_2026_08_11`). Sixteen other rows in
this probe are already tagged `[known]`; this one was not tagged when the
decision landed.

**Why it is worth a ticket rather than a shrug:** the probe's whole value is the
`new divergences: N` line. A permanent false 1 means a real find has to be
noticed *inside* a number that is never zero, and the next reader learns to skim
it — which is the failure mode the tagging mechanism exists to prevent.

## Work

Tag the row `known` (with the decision, not just a ticket slug, as the reason —
this one will never be "fixed"), or split it so the rows that genuinely still
differ from FPC are separated from the intended ones. Then `new divergences: 0`
means what it says again.

## Gate

`tools/fpc_diff_probe.sh` reports `new divergences: 0` on a clean tree.
