---
summary: "gate.sh's inline fixedpoint() demands convergence in ONE pass from pinned, so it reports RED for every change that alters the compiler's own emitted code — the exact mistake the Makefile documents as wrong"
type: bug
track: T
prio: 60
owner: claude-T@plexus
---

# `tools/gate.sh` fixedpoint does not iterate — false RED on any codegen change

- **Type:** bug — Track T (tools & testing)
- **Status:** done
- **Opened:** 2026-08-05
- **Found by:** Track A, gating
  `bug-a-static-array-of-managed-whole-assign-loses-data`.

## What happens

`tools/gate.sh`'s `fixedpoint()` is:

```sh
"$PINNED" compiler/compiler.pas "$a"
"$a"      compiler/compiler.pas "$b"
"$b"      compiler/compiler.pas "$c"
cmp -s "$a" "$b" && cmp -s "$b" "$c"
```

`A` is built from NEW source by the OLD pinned binary, so it carries the new
codegen; `B` is built by `A`. Whenever the change alters the code emitted for
`compiler.pas` itself, `A != B` — legitimately, and by exactly one generation.
`B == C` is the convergence. The gate requires `A == B` and so reports RED.

Measured on the ticket above: `gate.sh quick` → `FAIL self-host fixedpoint`,
while `tools/selfhost_fixedpoint.sh` on the identical tree →
*"converged after 2 round(s) from pinned: the compiler reproduces itself /
agrees with compiler/pascal26"*, and `testmgr --tier quick` 15/15 green.
The failure log is empty (`fixedpoint.log` is 0 bytes), so the summary line is
the only signal and it names no reason — which is what makes this cost a
detour rather than a glance.

## Why this is the known-wrong shape

The Makefile's `$(COMPILER)` rule already carries the fix and the reasoning, in
`chore-makefile-selfhost-iterate-to-convergence`:

> this rule used to demand byte-identical convergence in exactly ONE pass from
> whatever local seed happened to be on disk. […] "a stale seed legitimately
> needs an extra round (stage2 came from the OLD compiler, stage3 from the new
> one) — demanding one pass is what made a normal bootstrap look like a
> failure." testmgr already iterates for exactly this reason.

`tools/selfhost_fixedpoint.sh` iterates to `MAX_ROUNDS=4` and additionally
checks the hermetic fixedpoint equals `compiler/pascal26` (the Thompson-trap
property). gate.sh reimplemented the check inline and reintroduced the bug.

## Fix

Have `fixedpoint()` call `tools/selfhost_fixedpoint.sh` instead of open-coding
three rounds — it is the authoritative implementation, it iterates, and it
already enforces the stronger second property. If gate.sh must stay
self-contained, iterate to `MAX_ROUNDS` and accept the first round where two
consecutive stages agree, exactly as the Makefile rule does.

Either way, write the reason into `fixedpoint.log` on failure — an empty log
behind a `FAIL` line is what forced the manual bisect that produced this
ticket.

## Severity

Every Track A codegen fix trips it, and the prescribed per-fix loop in
CLAUDE.md is `make compiler/pascal26` + `tools/gate.sh quick`. A gate that is
red for the normal case trains agents to ignore it, which is worse than not
having it.

## Log
- 2026-08-08 — resolved, commit 487515c2f.


---

## Resolution (Track T, 2026-08-08) — commit `5d224133b`

Both tickets, one change: `gate.sh` had **re-implemented** a check that already
existed and reintroduced the bug that implementation had already been fixed
for. So the fix is not "iterate here too" — it is to stop having a second
implementation. `fixedpoint()` now calls `tools/selfhost_fixedpoint.sh`.

- It **iterates** to MAX_ROUNDS, so a legitimate one-generation lag (pinned
  does not yet emit what HEAD emits) converges instead of false-reding.
- It enforces the **anti-Thompson** property the inline version never checked
  (the hermetic fixedpoint must equal `compiler/pascal26`) — strictly stronger.
- It **prints its reason**. The old function sent every round to `/dev/null`,
  so a `FAIL` line sat above a 0-byte `fixedpoint.log` naming no cause. That
  empty log is what turned each occurrence into a manual bisect. Now 140 bytes
  with the verdict.

Exit 77 (no pinned stable) maps to a gate SKIP, not a failure.

### Honest limit on verification

**The false red is not reproducible at this HEAD.** pinned currently emits what
HEAD emits, so convergence takes 1 round and the old and new predicates both
pass. Seeding from the older v248 stable extracted out of git did not reproduce
it either — that generation agrees with HEAD too.

So the predicate difference is demonstrated on a **model** of the documented
shape (pinned one generation behind → A=gen1, B=gen2, C=gen2): the old
predicate fails on `A!=B` while `B==C` proves convergence; the new one passes
after 2 rounds. The field evidence stays the measurement in these tickets —
Track A saw `gate.sh` FAIL while `selfhost_fixedpoint.sh` reported "converged
after 2 round(s)" on the identical tree.

Gate: `gate.sh quick` GREEN (fixedpoint 28s, testmgr --tier quick 7s),
`fixedpoint.log` non-empty.
