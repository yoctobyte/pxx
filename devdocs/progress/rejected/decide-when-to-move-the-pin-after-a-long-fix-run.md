---
summary: "32 compiler fixes sit on master unpinned; Track B builds against pinned and has a workaround waiting on the move. Pin all at once, pin incrementally, or leave it — the brake is deliberate and this is a judgment call, not a default"
type: decision
track: U
status: rejected
prio: 60
---

# When should the pin move after a long run of fixes?

- **Type:** decision — Track U. **Escalated, not guessed.**
- **Opened:** 2026-08-05
- **Raised by:** Track A, after a night of bughunting on A+C+P.

## The situation

~32 compiler fixes have landed on `master` tonight, each gated per the per-fix
loop and pushed. **`make pin` has not run.** So:

- every other lane (B, and the frontends' library work) still builds against a
  `pinned` compiler that has none of them;
- `tools/gate.sh quick`'s pinned-seeded fixedpoint reports RED for everyone as a
  side effect — filed separately as
  [[bug-t-gate-quick-fixedpoint-goes-red-on-any-builtin-addition]];
- at least one Track B item is explicitly waiting on the move:
  `task-b-revert-pxxcio-clock-int64-cast-workaround`, which **must not** be
  reverted until the pin carries the fix it works around.

CLAUDE.md is deliberate that `make pin` is "the deliberate brake" and that
`make stabilize` alone does not move B's ground. It does not say *when* to
pull it, and that is correct — it is a human call about risk appetite.

## Why I am not deciding it

Pinning blesses all 32 at once, and they are not a uniform set. Some are narrow
and well-tested (a Char arm in `TextStrArg`); others changed shared ABI-adjacent
predicates (`RetViaHiddenDest`, `TypesCompatible`, forcing managed record params
by-ref) or replaced four backends' float emitters with one shim. The blast
radius differs by an order of magnitude across the set, and "it passed the quick
gate" is not the same claim as "it is safe to make everyone build on it".

The countervailing pressure is just as real: the longer the pin lags, the more
lanes are blocked on fixes that already exist, and the larger the batch that
eventually moves — which is the *worse* risk profile, not the better one.

## Options

1. **Pin now, whole batch.** Unblocks B immediately and closes the false-RED
   window. Accepts that a regression found later is bisected across 32 commits
   rather than caught at the boundary. Cheapest if Track T's matrix is green on
   the current SHA.
2. **Wait for Track T's full matrix on the current SHA, then pin.** The
   defensible default: the cross-target and corpus coverage the quick gate
   deliberately does not run is exactly what would catch an ABI-predicate
   mistake. Costs whatever the matrix latency is.
3. **Pin incrementally** — move to a SHA before the riskier ABI/float changes,
   let B unblock on the safe half, pin the rest after the matrix. More
   bookkeeping; smallest blast radius per step.
4. **Leave it** for the user to pull deliberately at review time. Status quo;
   the false-RED and B's blocked revert persist.

## Recommendation

**Option 2**, unless Track T is down. The changes that worry me are precisely
the ones the quick gate does not cover (cross-target ABI, the float shims on
i386/arm32/riscv32/aarch64), and that is what the matrix is for. If the matrix
is already green on a recent SHA, option 2 collapses into option 1 at no cost.

Option 3 is the answer only if the matrix comes back red on something specific
and B is genuinely blocked in the meantime.

## What unblocks on the answer

- `task-b-revert-pxxcio-clock-int64-cast-workaround` (Track B)
- the false RED in [[bug-t-gate-quick-fixedpoint-goes-red-on-any-builtin-addition]]
  (partially — that gate is worth fixing regardless)


## REJECTED 2026-08-06 — user's call: bogus ticket

Rejected on review with the user. Two independent reasons, both mine:

**1. It re-litigated a decided question.** [[decide-track-t-autopin-criteria]]
was decided 2026-08-01 — *option D, never auto-pin; a human runs `make pin`,
matching current practice*, deferred until the baseline is stable enough to
automate against. The policy was settled. This ticket should at most have
asked "is now the time", and instead re-opened "what is the rule". I did not
read the sibling decision before filing.

**2. Its recommendation cited an unreachable criterion.** I recommended
"wait for Track T's full matrix, then pin". That same decided ticket records
that the full tier was *permanently* RED — 18 jobs on xeon, 16 on borg, every
one ticketed or advisory — and that a naive "pin when green" rule would
**never fire**. I recommended waiting for something that structurally could not
happen.

## What was actually true when this was reviewed

The baseline had moved. At `cc4116ba900d` the full tier went **GREEN** —
native, full and opt — clearing 15 jobs, and that red set was *entirely* the
riscv32 cascade this session caused and fixed (`6532d45ac`). Nothing else was
red. As far as the tstate record shows this is the first fully green full
matrix, and HEAD at review time was 6 commits past it with **no `compiler/` or
`lib/` change** among them.

So the question this ticket asked had no judgment left in it.

## The one thing worth carrying forward

`decide-track-t-autopin-criteria` deferred option A (baseline allowlist)
explicitly *"until the baseline justifies the machinery"* — "clear the ground
first, then revisit once 'stable enough to pin' is a much shorter, more
tractable list". **That trigger has now fired**: the list is empty, not shorter.

That is a real successor question — *build auto-pin now that the baseline is
green?* — and it belongs on Track T/U as a fresh item against the decided
ticket, not as this one. Filed nothing automatically; raising it with the user
rather than guessing that a first green sweep is a durable enough baseline to
automate against.

Note for whoever reads this next: **no auto-pin machinery exists today.** Every
`pin` reference in `tools/twatch.py` concerns reseeding a gate *from* the
pinned binary; none moves it. Waiting for T to pin will wait indefinitely.
