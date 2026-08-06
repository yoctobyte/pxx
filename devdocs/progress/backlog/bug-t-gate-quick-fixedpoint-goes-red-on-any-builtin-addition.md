---
summary: "tools/gate.sh's fixedpoint seeds from PINNED and demands A==B==C, so it goes RED for every agent after any new builtin lands and stays red until re-pin — indistinguishable from the agent's own breakage"
type: bug
track: T
prio: 55
---

# `gate.sh quick` reports RED for a stale pin, not a real fixedpoint failure

- **Type:** bug — misleading gate. Track T (owns `tools/gate.sh`).
- **Opened:** 2026-08-05
- **Found by:** Track A, while gating an unrelated parser change.

## Symptom

`tools/gate.sh quick` at a clean HEAD:

    FAIL  self-host fixedpoint  (23s)
    PASS  testmgr --tier quick
    gate: RED

with an **empty** `fixedpoint.log`, so there is nothing to read.

## Cause

```sh
fixedpoint() {     # self-host from the PINNED seed: A == B == C, byte for byte
  "$PINNED" compiler/compiler.pas "$a" || return 1
  "$a"      compiler/compiler.pas "$b" || return 1
  "$b"      compiler/compiler.pas "$c" || return 1
  cmp -s "$a" "$b" && cmp -s "$b" "$c"
}
```

`A` is built by **pinned**; `B` by A. So `A == B` asserts that pinned already
emits what HEAD's compiler emits. Add a builtin and that is false by
construction: pinned does not know it, HEAD does, so B gains symbols A lacks.

Measured at HEAD today — the A/B map diff is exactly today's new builtins:

    InterLockedCompareExchange … InterLockedIncrement64   (10)
    PXXArrayReleaseImmediate
    PxxSciDigits17, PxxSciMul, PxxSciSplit
    StrChar

`B == C` holds. **The compiler does reach a fixedpoint** — it just is not
pinned's fixedpoint, and cannot be until `make pin` runs.

## Why this matters more than it looks

The failure is **indistinguishable from the agent's own change breaking the
self-host gate**, which is the one property CLAUDE.md says can never leave a
tree. So the honest response to a red here is to stop and bisect — which is
what it cost today, on a change that turned out to be innocent (reverting it
gave the identical A≠B, B==C).

Every lane running `gate.sh quick` between a builtin addition and the next
`make pin` sees this. That window is currently open and ~32 commits long.

It also contradicts the per-fix loop, which says `make compiler/pascal26`
**is** the byte-identical fixedpoint — and that is green throughout
(`converged after 1 round`). Two gates named the same thing disagree, and the
stricter one is the one that prints RED.

## Suggested direction (Track T's call)

The pinned-seeded `A == B` is a genuinely useful property — it is what proves
the pin is still current. It is just not a *per-fix* property. Options:

1. **Report it separately.** Keep the three rounds, but only fail on
   `B != C` (true non-convergence, the dangerous case) and report `A != B` as
   an informational `pin is N commits stale` line rather than RED.
2. **Seed from `latest` instead of `pinned`** for the quick tier, keeping the
   pinned seed for `full`.
3. **Leave it and re-pin more often** — but that inverts the pin's role as
   the deliberate brake.

(1) looks right: it keeps the real safety property as a hard failure, keeps the
staleness visible, and stops the false alarm.

Either way **write something to `fixedpoint.log`** — which pair differed and
their sizes. An empty log on a failing step is most of why this was expensive.

## Related

- The pin question itself is parked as
  [[decide-when-to-move-the-pin-after-a-long-fix-run]] (Track U) — this ticket
  is about the gate lying, not about when to pin.

## Gate

A clean HEAD with a stale pin does not report RED for that reason alone; a
genuine non-convergence (`B != C`) still does; `fixedpoint.log` names the
differing pair either way.


## 2026-08-06 — diagnosis CONFIRMED by pinning

`make pin` moved `pinned` to v244. `tools/gate.sh quick` immediately went
**GREEN**, self-host fixedpoint included, with no code change between the RED
and the GREEN:

    before pin:  FAIL  self-host fixedpoint  (empty fixedpoint.log)
    after pin:   PASS  self-host fixedpoint  (27s)

That is the predicted behaviour exactly: `A == B` asserts "pinned already emits
what HEAD emits", so it is false from the moment a builtin is added until the
next pin, and true again immediately after. The compiler was never
non-convergent — `B == C` held throughout.

The ticket stands: this **will** recur on the next builtin addition, and the
next agent will again see a RED that is indistinguishable from having broken
the self-host gate. The empty `fixedpoint.log` remains the largest part of the
cost.
