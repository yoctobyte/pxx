
---

## Resolved 2026-08-29 — frankA

Second arming rule in `tools/gate.sh`: the canary also fires when
`origin/master`'s `compiler/` has moved past the last sha **this clone** proved
green, recorded in `$GIT_DIR/pxx-seed-green`. Untracked and per-clone on
purpose — "seed-green" is a property of a box that ran fpc, not of a commit,
and tracking it would let one box's green silence every other box. The sha is
recorded only when the working tree's `compiler/` is clean against HEAD;
with edits in flight, what was proved is not any sha, and stamping HEAD would
suppress the next run for a state never built.

The misattribution half is fixed at the same time, and it is the half that
costs hours: on FAIL the gate now leads with whose break it is, from
`seed_mine` (does this tree have any local `compiler/` change at all), before
saying what it might be. It also names BOTH failure shapes — the existing
MISSING-forward advice actively misdirected here, where the defect was a
forward too many.

**Verified on the live defect, before and after.** On this tree, clean, with
the duplicate forward sitting on origin/master:

- old rule — `git diff merge-base -- compiler/` empty → not armed → `SKIP`,
  break unreported. Two gates on this box had printed `PASS` for exactly this
  reason earlier in the day.
- new rule — nothing proved on this clone → armed → runs fpc → `FAIL`, with
  `NOT YOUR CHANGE: no local compiler/ edits — this break is already on
  origin/master. Do not bisect your own work.`

Gate: `tools/gate.sh quick` at `71dd35092`, self-host fixedpoint `60b060bb54a8`.
The seed step went RED as designed; every other step passed. That RED was the
upstream duplicate forward, since deleted by Track R in `20efe74ef`.

Not done here, deliberately: `tools/forwardlint.py` gaining duplicate-forward
detection — the coordinator took that and landed it as `52eb9dc2f`.
