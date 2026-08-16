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

## The same blind spot costs far more in pasmith (measured 2026-08-16)

`tools/pasmith_run.py --wide --minutes 25 --start 90000` reported **88
divergences**, every one `pxx-vs-fpc_*`, with pxx self-consistent across
-O0/-O2/-O3 and FPC self-consistent across its two. That reads as a compiler in
flames.

It is one thing: the shift deviation, in the checksum of nearly every generated
program (`--wide` seed 90010 alone has 24 `shl`/`shr` sites). The control —
rewrite `shl`->`+` and `shr`->`-` in the generated source and run both again:

```
seed 90010 (shifts neutered)   pxx = 17238490836835624514
                               fpc = 17238490836835624514   <- exact
```

So the fuzzer's FPC oracle is unusable as it stands: a real miscompile would
arrive as divergence number 89. Options, cheapest first:

1. **Generate shift counts that cannot observe the difference** — the deviation
   is only visible when the count reaches or passes the operand's declared
   width, so masking the generated count to `width-1` keeps the whole operator
   in the grammar and makes FPC an oracle for it again.
2. Emit the shift through a helper that truncates to the declared width when
   the program is built for the FPC oracle (a `{$ifdef FPC}` shim in the
   generated preamble).
3. Give the ledger a known-deviation signature, as the probe's `known/filed`
   list already does — the weakest, because it can only recognise the shape it
   has seen.

(1) is the recommendation. Whichever lands, the FPC-probe row above should use
the same mechanism, since it is the same fact.
