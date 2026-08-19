---
track: U
prio: 55
type: decide
owner: unassigned
blocked-by: []
summary: "A -O0-only self-compile failure passed the per-fix gate, the self-host fixedpoint, and every Track T tier — the class is structurally invisible. Widening the gate would catch it and would also lengthen the loop CLAUDE.md is emphatic about NOT widening. Genuine fork; coordinator must not settle gating policy."
---

# Decide: should the gate prove self-compile at more than one `-O` level?

Raised by Track T while handing off
[[bug-a-self-compile-at-o0-overflows-the-code-buffer]], and explicitly left unfiled by it
("should be filed separately if A wants it rather than assumed"). **Filed as a decision
rather than actioned, because gating policy is not the coordinator's to change.**

## The fork

`make compiler/pascal26` compiles `compiler.pas` at the **default** level, and the
fixedpoint proves byte-identity **at that level**. Nothing in the per-fix loop, and no
Track T tier, compiles the compiler's own source at `-O0`. So this entire class —
*compiler builds itself at one `-O` level and not another* — is structurally invisible
until something incidental trips over it. Here, a bench row-count drop did.

**Option A — leave the gate alone.** The class is real but was caught anyway, by Track T's
bench, within hours.

- *For:* `CLAUDE.md` is emphatic that the per-fix loop is the whole gate and must not be
  widened — that rule exists because agents kept reaching for the full suite, and it was
  enforced with a hook after being ignored twice in one session. Every second added to a
  ~42s loop is paid on **every fix by every agent forever**. And breadth is explicitly
  Track T's job, run asynchronously against the pushed sha, which is exactly what
  happened here.
- *Against:* it was caught by luck of a benchmark existing, not by design. A `-O0` break
  with no benchmark touching it would sit indefinitely.

**Option B — add a second `-O` level to the self-compile check.** In the per-fix loop, or
in a Track T tier.

- *For:* closes a structurally invisible class. `-O0` is the level a human reaches for
  when debugging the compiler, so it failing is worse than its rank suggests.
- *Against:* cost, and where it lands matters — in the per-fix loop it taxes every agent;
  in a T tier it is nearly free but only catches things after the push, which is what
  already happened. **If the answer is a T tier, the honest description is "make the
  existing accident deliberate", not "close the gap".**

## Recommendation

**Option B, but in a Track T tier — not in the per-fix loop.** The loop's shortness is
load-bearing and hard-won; the asynchronous matrix is where breadth belongs, and this
case is evidence the split works rather than evidence against it. Making it deliberate
costs nothing per fix and removes the dependence on a benchmark happening to exist.

**Not recommended:** widening the per-fix loop. That trade has been made deliberately,
twice, and written into `CLAUDE.md` as the single source of truth on gating.

## What the answer changes

- Whether a Track T ticket is filed to add the tier job (T owns tier composition).
- Whether `CLAUDE.md`'s claims-discipline section should note that "self-host fixedpoint"
  means *at the default level* — worth doing **regardless of the outcome**, since the
  phrase is used as evidence of general soundness and is scoped more narrowly than it
  reads. See `project_the_self_host_gate_proves_one_optimisation_level`.

## MATERIAL UPDATE 2026-08-19 — `-O0` was a LEADING INDICATOR, not just extra coverage

The fix (`6b2402b92`) measured what the ticket had only framed, and it changes the
argument above. **It was never an `-O0` problem.** Emitted code size for `compiler.pas`:

```
-O2 / default   7 415 348 B      -O1  7 458 182 B
-O3             7 561 519 B      -O0  8 394 698 B   <- over the 8 388 608 cap by 0.07%
```

**All four levels sat at 88-90% of the cap.** `-O0` was simply first across a line every
level was standing on, and ordinary growth would have taken the **default** build down
next. `MAX_CODE` is now 16 MB and the default build sits at 44%.

**So the `-O0` self-compile was not merely covering an invisible class — it was an early
warning of a condition about to break the level the gate DOES check.** That is a
materially stronger argument for Option B than the one I wrote above, which only claimed
it closed a blind spot. A check that fails first, cheaply, on a shared underlying
condition is worth more than its own coverage.

**The counter-argument does not move, though, and should not be lost:** this still says
nothing about *where* the check belongs. A Track T tier catches a leading indicator just
as well as the per-fix loop does, days earlier than the thing it predicts, and costs no
agent anything per fix. The recommendation stands: **Option B, in a T tier, not in the
loop.**

**Also worth folding in wherever this lands:** the failure was confusing because of an
inversion now named in the error text — **lower `-O` levels emit MORE code, so a build
that fits at `-O2` can still overflow at `-O0`.** Anyone reasoning about "does it build"
from the default level alone will get that backwards.

---

# DECIDED 2026-08-19 by the user — a Track T tier, and for a DIFFERENT reason than filed

> "Track T was right with the -O level — although this size limitation was just to protect
> ourselves from run-away issues. Also, it should not hinder quick-gating. Apart from that
> it sort of makes sense. **Not because of -O0, but more of -O1-2-3-? and in particular
> when we start more work on optimizing.**"

**Decision: yes, in a Track T tier. Explicitly NOT in the per-fix loop** — quick-gating
must not be slowed. The loop stays `make compiler/pascal26` + repro + `gate.sh quick`.

## The rationale is corrected, and this matters for what gets built

Both arguments in this ticket — mine ("closes an invisible class") and the updated one
("`-O0` was a leading indicator of the code buffer filling") — are **about size, and both
are now spent.** `MAX_CODE` was only ever a runaway guard, not a real constraint; raising
it 8 MB to 16 MB cost virtual BSS and nothing else, and the default build went from 88%
to 44%. Size will not be the thing that catches anything again for a long time.

**The value is CROSS-LEVEL DIFFERENTIAL COVERAGE, and it grows with Track O.** If the
compiler built at `-O0` and the compiler built at `-O3` disagree about anything, that is
an **optimizer bug** — and `compiler.pas` is by far the largest, most edge-case-dense
program we have to run the optimizer over. As optimization work ramps up (new `-O3`
passes, promotion to `-O2`), a job that compiles the compiler at every level and compares
is the cheapest optimizer-differential we own. **Build it as a differential across levels,
not as a "does `-O0` still work" check.**

## Most of the mechanism already exists

The bench harness already reports `CANARY-DIFF vs -O0` for `-O2` and `-O3` on the
`selfcompile` rows — precisely a cross-level comparison, and what surfaced the original
failure. So this is largely **formalising an existing canary into a tier job**, not
building one from scratch. Track T owns tier composition and should size it.

## Also doing, because it is true regardless of this outcome

`CLAUDE.md`'s claims-discipline section now records that **"self-host fixedpoint" means at
the DEFAULT optimisation level.** The phrase is routinely used as evidence of general
soundness — the coordinator used it that way to argue a bench red could not be a compiler
bug, and was wrong — so the scope belongs next to the claim.

## Re-filed as work

See `feature-t-tier-job-self-compile-differential-across-o-levels`.
