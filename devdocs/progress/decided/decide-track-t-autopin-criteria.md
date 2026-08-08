---
summary: "What criteria justify Track T auto-pinning a stable binary?"
type: decide
track: U
prio: 55
status: resolved
resolved: 2026-08-08
---

## REOPENED AND DECIDED 2026-08-08 — option A, starting in SHADOW MODE

**User's call, superseding the 2026-08-01 answer below.** The deferral
condition set then has been met, so the question was re-put and answered:
**option A (baseline allowlist) with K >= 2 consecutive qualifying shas and
auto-rollback, beginning in shadow mode.**

**What changed — the ground cleared, exactly as the deferral anticipated.**
The 2026-08-01 blocker was that "all green" could never fire against 18 red
jobs on xeon and 16 on borg. Measured on plexus at `450bb7f86a75`:
**2180 of 2182 jobs pass.** The 15-job cross-target cascade, `test-asm` and
`test-zlib` are all gone from the red list. The only live red was
`test-uforth#00 = timeout`, a Track T harness bug (the job was classed `unit`,
a 90s budget, and Track N's 13 ANS word sets took it past ten minutes) fixed in
`394c4f217`.

**Shadow mode landed in `6a4502611`** — `pin_shadow()` in `tools/twatch.py`.
It moves nothing: no `pinned`, no `make pin`, no `stable_linux_amd64/**`. It
records the decision it WOULD have made to `tstate/pin-shadow.log` so a week of
them can be compared against what a human actually blessed.

Criteria as implemented:

- red set ⊆ `tstate/pin-allowlist.tsv`, and **every entry must name a ticket**
  or it is refused at load and printed as ignored — the anti-dumping-ground
  rule that makes option A worth having;
- **self-host byte-identical is never waivable**, by allowlist or by streak;
- K >= 2 consecutive qualifying shas;
- only the `full` tier may qualify a pin.

The allowlist **ships empty**, which is the honest state — nothing currently
needs waiving. If it is still empty when shadow mode ends, that is the
strongest available argument that the automation is safe.

**Still to settle before the live cutover** (the 2026-08-01 "also to settle"
list is still open, plus one):

- **auto-rollback**, the second guard — belongs with the cutover, since there
  is nothing to roll back in shadow mode;
- does a pin require the `opt` tier green too, or only `native` + `full`?
  (implemented today as `full` only);
- who may pin when the allowlist itself changed in the same window?
- should pinning pause while any `urgent/` Track A ticket is open?

**Note on the motivation.** The user's stated reason was that "stabilizing and
pinning takes many minutes" of other tracks' downtime. That is largely a
*scheduling* problem, addressed by
[[feature-t-testmgr-owns-pinning-interruptible]] — moving the pin gate into
testmgr as an interruptible background job removes the wait whether or not
pinning is ever unattended. Worth doing regardless of how the cutover lands.

---

## Superseded: DECIDED 2026-08-01 — option D (never auto-pin) for now

**User's call.** No auto-pin machinery yet — a human runs `make pin`,
matching current practice. Reasoning: the fact that a naive "all green"
rule would never fire (18/16 permanently red jobs, all ticketed/advisory)
is itself a sign the baseline isn't stable enough to safely automate
against yet. Building the allowlist-plus-guards machinery (option A) on
top of an unstable baseline is complexity in the wrong order — clear the
ground first (work down the known-red list, close the advisory-vs-real
gap), then revisit whether A's criteria are worth automating once "stable
enough to pin" is a much shorter, more tractable list. Not rejected,
deferred until the baseline justifies the machinery.

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
