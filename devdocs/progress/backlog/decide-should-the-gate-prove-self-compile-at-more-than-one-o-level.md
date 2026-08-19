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
