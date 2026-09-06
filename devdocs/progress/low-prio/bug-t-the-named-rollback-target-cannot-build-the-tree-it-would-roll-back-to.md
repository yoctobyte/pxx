---
track: T
prio: 30
type: bug
status: low-prio
found: 2026-09-05
found-by: frankZ
owner: ""
blocked-by: []
summary: "`trackt pinstatus` names v354 as the fallback pin and `pin_is_green()` selects it, but v354 CANNOT COMPILE ANY of today's 54 lib/rtl root units (54/54, `undefined variable (__pxxblockmove)`). Measured across nine pins: v404 fails 2, v375..v403 all fail 14, v365 and v354 fail 54. So the usable rollback depth is ZERO — every historical pin is strictly worse than the current one — and CLAUDE.md's rollback preference is INVERTED: it prefers the green pin, which is the worst target, over the most recent, which is the best. `make revert` restores only the stable dir, never lib/rtl, so a rollback is incoherent by construction."
---

# The named rollback target cannot build the tree it would roll back to

## The claim, measured

Nine pins swept over **today's** `lib/rtl`, using `gate.sh`'s own
`pinned_rtl_canary` discovery and probe verbatim (54 root units — units no other
`lib/rtl` unit `uses`), each binary extracted from git:

| pin | date | fails / 54 | cause |
| --- | --- | --- | --- |
| HEAD `5ec14c826891` @ `8374118ec` | 09-05 | **0** | — |
| v404 `fe1e9c37` | 09-05 | **2** | `pyvar_is_*tag`, clears at the next pin |
| v403 `ce63beeeb` | 09-04 | **14** | `unknown type: TMethod` |
| v400 | 09-02 | 14 | same |
| v398 | 08-30 | 14 | same |
| v395 | 08-30 | 14 | same |
| v390 | 08-29 | 14 | same |
| v385 | 08-27 | 14 | same |
| v375 | 08-26 | 14 | same |
| v365 | 08-19 | **54** | `undefined variable (__pxxblockmove)` |
| **v354 `1fffc8cf5c3e`** — **the named fallback** | 08-19 | **54** | same |

Controls run, not assumed: the canary's own positive control (a program naming a
type no compiler has must be REJECTED) passes for v354, so the sweep is reaching
a compiler; root discovery found 54, above the canary's own `>= 20` floor; and
the HEAD arm fails **0 of 54**, so every row above is the seam and not ordinary
breakage.

## Why this is not "there is no fresh rollback target"

That is the known framing and it understates the problem. The target is not
missing. **It is named, it is selected automatically, and it is the worst
available option.**

`trackt pinstatus` prints, today:

```
pin v404  fe1e9c37  5b5fdb0b  2026-09-05T18:15:57Z
  full    RED     **host capability absent: rdrand, demos#00  (seven)
  last pin T found fully green: v354  (19d5d9c7)
  (green = a `full` run judged this sha and no tier was RED; `make revert` demotes)
```

A reader takes the last two lines as advice: the current pin is red, here is the
good one, here is the command. Following it moves the tree **from 2 broken root
units to 54**.

## The mechanism, and it is structural

`pin_is_green()` asks *"was this sha's tier GREEN when T judged it"* — a question
about the **past**. A rollback target must answer *"can this pin build the tree I
have NOW"* — a question about the **present**. The two differ by every `lib/rtl`
commit since, and `lib/rtl` freely uses compiler builtins.

Each builtin that lands and gets used from `lib/rtl` cuts a cliff. Two are
visible in the table and both are dated:

- **2026-08-21 `0f6a04644`** `feat(A): IR_BLOCK_MEM` introduces `__pxxblockmove`;
  **`2b85f8c8f` the same day** puts it in the RTL's bulk memory routines. Those
  are reached by the unit every root pulls in, so a pin older than 08-21 fails
  **all 54**. v354 and v365 are 08-19.
- **2026-09-04 `31f8b11bf`** `feat(P): System.TMethod` mints the builtin;
  `lib/rtl/typinfo.pas` uses it and deliberately does **not** redeclare it
  (its own comment says so). Any pin older than that fails the **14** roots that
  reach typinfo.

So the step function is not noise and not a coincidence of two bad pins — it is
one cliff per builtin, and the rate is roughly one per fortnight lately.

`make revert` cannot help with this, by construction. It does
`git checkout $SRC -- $(STABLE_DEFAULT_DIR)` and nothing else: **the pin moves
back and `lib/rtl` does not.** There is no version of that command that produces
a coherent pair, because the pair is only coherent within one era.

## The doctrine this falsifies

CLAUDE.md, Track A's per-lane facts:

> Rollback prefers a green pin and falls back to the most recent, so recovery is
> never empty.

**The preference is inverted.** Against the current tree the green pin is the
worst target available and the most recent is the best. "Recovery is never empty"
is true and not the useful property; recovery is never *empty*, it is *harmful*.

That matters beyond this ticket because the adjacent rule leans on it:

> A red is a reason to pin SOONER, not later — the pin in place is red too, and
> refusing on reds is an argument for never leaving a red pin.

That argument is sound **only while recovery works**. It is the recovery half of
the fast-pin trade (`devdocs/dev/track-t.md` — *"a bad pin is recovered, not
prevented"*), and the measurement above says that half has not existed for some
time. This is not an argument for gating pins — CLAUDE.md is explicit that a
valid pin is the self-host fixedpoint and nothing else may block one, and
**nothing here should be read as a reason to refuse a pin.** It is an argument
that the *recovery* claim needs to become true again, or stop being cited.

## What would fix it, in rough order of cost

1. **Cheapest and most of the value: stop naming a target nobody validated.**
   `pinstatus` already has the canary's logic available. Either run the 54-root
   sweep against the candidate before printing the line, or print the line with
   an explicit *"not validated against the current lib/rtl"*. A number that is
   checked and a number that is merely recorded must not print identically.
2. **Make `pin_is_green()` ask the present-tense question**, or rename it — it is
   currently a truthful answer to a question no caller is asking. Callers want a
   rollback target; it returns a historical verdict.
3. **The real repair is pairing.** A pin and the `lib/rtl` of its era are one
   artifact. Either `revert` moves both, or the pin records the `lib/rtl` tree it
   is coherent with so a rollback can say *"this pin cannot build your tree"*
   instead of silently producing one that cannot.

(3) is a design change and probably wants a `decide-`. (1) is small, and it is
the difference between an advisory that misleads and one that says it does not
know.

## Not established here

- **Whether any pin in the log can build today's `lib/rtl` cleanly.** Nine were
  swept, chosen to bracket the cliffs, not exhaustively. The best observed is the
  current pin at 2 of 54. I did not search for a zero.
- **Whether the same holds for `lib/pcl`, `lib/crtl` or `examples/`.** The canary
  covers `lib/rtl` roots only, so this ticket's numbers do too.
- **Box and toolchain**, since the whole finding is about instruments being
  correct about the wrong thing: measured on **plexus**, kernel 7.0.0-30-generic,
  against `compiler/pascal26 = 5ec14c826891` built at `8374118ec`
  (`converged after 1 round(s)`, a real recompute). No qemu is involved — every
  probe is a native x86-64 compile, which is why this one number is not subject
  to the usual cross-target caveat. seven's qemu is 10.2.1 and is irrelevant to
  these rows.

## 2026-09-06, frankuser — MOVED TO low-prio/, 80 -> 30. The owner ruled out the remedy, not the measurement.

**The measurement stands. Nothing here is retracted.** This moves for the same
reason `umbrella-one-full-tier-run-with-no-red-tier` went 85 -> 55 tonight, and
it is the second ticket in one evening whose rank rested on rollback.

CLAUDE.md now records, owner 2026-09-06: *"yes we avoid rollbacks. useful work
done is work done, even if (other) things break."* And, verbatim: **"do not rank
a ticket on rollback depth and do not spend work making `make revert` produce a
coherent pair."** This ticket's remedy IS that work. It sat at prio 80 — above
almost everything on the T queue — for a job the owner has said we do not do.

**`low-prio/` and not `rejected/`, deliberately.** `rejected/` means the report
is wrong; this one is true and reproducible, and CLAUDE.md's own rollback rule
cites this measurement as part of its evidence. `low-prio/` is the folder for
real, correct, no-plan-to-act — which is exactly the state. Not `rainy-day/`
either: that folder is for work we intend to do later, and there is no such
intent here.

**A prio is a claim about attention, and 80 was making one the owner had already
denied.** The ranker cannot read the handbook.

**Flagged by frankZ, moved by me, and the split is the point:** frankZ found it
while re-ranking its own umbrella for the identical reason and declined to move
someone else's ticket on its own reading, handing it to an active seat instead.
frankH had earlier declined to re-rank frankZ's umbrella on the same grounds.
**Two seats in one evening correctly refused to act unilaterally on a ranking
they believed was wrong, and both were right to refuse and right about the
ranking.** The cost of that caution is one message; the cost of getting it wrong
is a silent re-rank nobody can find.

**Its neighbour `bug-t-pin-verify-builds-with-the-previous-pin-not-the-one-it-names`
STAYS at 80 and is untouched by this.** That one says every pin verify builds
with pin v(N-1) while recording the verdict under vN — an instrument lying about
which binary it measured, which is a live correctness problem regardless of
whether anyone ever rolls back.
