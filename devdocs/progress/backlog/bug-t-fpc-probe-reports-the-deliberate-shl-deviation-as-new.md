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

## 2026-08-16 — both halves fixed, and the recommended fix was already in place

### The probe: a third tag, because `known` was the wrong word

Gate met: `new divergences: 0   known/filed: 16   by design: 1   no-oracle skips: 0`.

Not tagged `known`, though — `known` promises the row is *temporary*, so the
list reads as a backlog and a row that can never leave it corrupts the count in
the other direction. `probe()` now takes a third tag, `bydesign`, which
**requires a reason** and prints it under the DIFF line:

```
DIFF [by design] shl-shr-neg            fpc=[2147483644|-16] pxx=[9223372036854775804|-16]
           ^ shl/shr compute at NATIVE width and never truncate to the declared
             type (decided 2026-08-11). ... Permanent -- do NOT "fix" it to match.
```

The reason is mandatory because it is the whole point: a permanent deviation
has to carry the decision that made it permanent, or the next reader cannot
tell it from a bug someone forgot to file.

### pasmith: recommendation (1) was already implemented, and it does not work

Worth stating plainly, because it would have been landed as a no-op. The
generator has masked shift counts to `ty.bits - 1` all along — the code and its
comment both say so. So the premise the recommendation rests on, *"the deviation
is only visible when the count reaches or passes the operand's declared width"*,
is **false**, and the outer `ty(...)` cast does not rescue it either: pxx does
not narrow the shift result on that cast.

Measured instead of reasoned — one variable per type, count masked, in exactly
the shape pasmith emits, negative/large value, all eight integer types x
{shl, shr}. **Exactly one of the sixteen cells diverges:**

| | fpc | pxx |
| --- | --- | --- |
| `longint shr` | 2147483644 | **-4** |

Everything else agrees, and the reason each one agrees is the useful part:

- **shortint / smallint `shr`** agree because truncating back to 8 or 16 bits
  discards precisely the high bits the two promotions disagree about.
- **int64 `shr`** agrees because 64 bits *is* pxx's native width.
- **every `shl`** agrees at every width, including with values that overflow the
  declared type (`longint(2000000000) shl 5` etc. — verified), because `shl`
  moves bits UP and out, so the surviving low bits are identical whether the
  promotion was to 32 or 64.

So this was never a general shift problem, and never a `shl` problem despite the
ticket's title: it is **signed `shr` at exactly the width where FPC's 32-bit
promotion and pxx's 64-bit promotion differ.**

### The fix: `shr` shifts the unsigned sibling

`shr` now reinterprets a signed operand through the same-width unsigned type
(`longint` -> `longword`, and so on) before shifting, then casts back. That is
what Pascal's `shr` actually specifies — a LOGICAL shift, which only has an
unambiguous meaning on an unsigned value — so both compilers agree at every
width. `shl` is untouched.

Applied uniformly rather than carving out `longint` alone, per
`normalise-dont-special-case.md`: a rule with one width excepted is the second
path that quietly stays broken.

**What it costs.** The FPC oracle loses no coverage it ever had — it could never
judge signed `shr`. The pxx-vs-pxx O-level oracle does lose the signed-`shr`
codegen path, and that is a real if small loss, accepted here because an oracle
that reports 88 divergences of which 0 are real is worth less than one that
covers slightly less and can be believed.

### Verified

- `pasmith_run.py --seed 90010 --wide` — the ticket's own worked example, which
  had 24 `shl`/`shr` sites: **0 divergences.**
- `pasmith_run.py --check 60 --wide` — the generator gate the tool asks for
  after any `pasmith.py` change: **60 seeds, 0 rejected by FPC** (28.5s).
- `tools/fpc_diff_probe.sh` — `new divergences: 0`.
- `pasmith_run.py --wide --minutes 12 --start 90000` — the same seed range that
  produced this ticket's **88 divergences**: **192 programs, 0 divergences**
  (0 FPC-rejected, 0 known, 0 NEW). Half the ticket's wall-clock, so fewer
  seeds, but the range is the one that was on fire.

The oracle is usable again: the next `pxx-vs-fpc_*` this fuzzer reports will be
a real one, arriving as divergence number 1 rather than number 89.
