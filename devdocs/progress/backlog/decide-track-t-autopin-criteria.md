---
summary: "What criteria justify Track T auto-pinning a stable binary?"
type: decide
track: U
prio: 55
---

# decide: what lets Track T pin automatically?

- **Type:** decision (Track U) — filed by `claude@borg` 2026-07-31
- **Origin:** user set the direction ("xeon main task is Track T — find
  regressions; in future, pin when stable"). The *direction* is decided; the
  **criteria** are not, and they cannot be guessed safely.

## Why this needs you and not a default

`make pin` moves `pinned`, which is **the ground every other track builds on**
(B, C, D, E all build with `$(PXX_STABLE)`). A bad pin does not fail one job —
it silently rebases everyone onto a broken compiler. So the cost of pinning too
eagerly is asymmetric against pinning too late, and the threshold is a judgment
call about that asymmetry, not a fact in the code.

## The blocker: "all green" would never fire

The full tier is **permanently RED today** — 18 jobs on xeon, 16 on borg — and
every one is either ticketed or advisory:

- `fpc-bootstrap` — advisory by construction (`fpc_canary_job()` sets
  `advisory = True`; gates nobody's push)
- the 15-job cross-target cascade — `regression-cascade-b45c759f9e65`
- `test-asm` — [[bug-elf-missing-pt-gnu-stack]]
- `test-zlib` — gcc-14+ oracle break

A naive "pin when the matrix is green" therefore never pins. Any workable rule
needs a notion of **known-baseline reds**.

## Options

**A — Baseline allowlist (recommended).** Pin when
`red_set ⊆ known_baseline` AND self-host byte-identical AND K consecutive shas
qualify. The allowlist is explicit, lives in the repo, and **every entry must
name its ticket** — so it cannot quietly become a dumping ground. A *new* red
blocks pinning; a known one does not.
*Cost:* someone must curate the allowlist. That is the point — it makes
"we are shipping with these known breaks" an explicit, reviewable statement.

**B — Advisory-flag only.** Pin when every non-`advisory` job is green.
*Cheaper* (testmgr already carries the flag) but pressure lands in the wrong
place: it invites marking jobs advisory to unblock a pin, which is exactly how
a suite rots.

**C — Native-only gate.** Pin on native green + self-host byte-identical,
ignore the matrix.
*Fast*, and matches "dev does not wait for the gate" — but it pins binaries
never validated cross-target, and cross-target reds are most of what Track T
exists to catch.

**D — Never auto-pin.** Track T proposes (files a ticket "sha X qualifies"), a
human runs `make pin`.
*Safest*, keeps a human on the one irreversible-ish step, costs latency.

## Recommendation

**A, with two guards:**
1. **K ≥ 2 consecutive qualifying shas** before pinning — one clean matrix can
   be luck, and today proved the suite has phantom reds (5 unrelated jobs went
   NEW-RED then FIXED with no capable commit between).
2. **Auto-rollback:** if the first matrix *after* a pin shows a new red, move
   `pinned` back and file urgent. Pinning must be as reversible as it is
   automatic.

Start in **shadow mode** — Track T logs "would have pinned sha X" for a week
without moving anything. Compare against what a human would have blessed. That
costs nothing and answers the question with evidence instead of argument.

## Also to settle

- Who may pin when the allowlist itself changed in the same window?
- Does a pin require the `opt` tier green too, or only `native` + `full`?
- Should pinning pause entirely while any `urgent/` Track A ticket is open?

## Notes

Filed per the escalation rule in [`two-box-protocol.md`](../../dev/two-box-protocol.md):
an agent that hits a fork it cannot settle files `decide-*` and moves on rather
than guessing. Whichever agent has the user in front of it should surface this.
