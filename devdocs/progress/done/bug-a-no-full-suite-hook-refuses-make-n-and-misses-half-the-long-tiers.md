---
track: A
prio: 45
type: bug
summary: "`.claude/hooks/no-full-suite.sh` (1d0e227a8) refuses `make -n`, which is a DRY RUN that executes nothing and is how testmgr and the TESTTMP verification protocol read recipes — and the refusal is bypassable by an unrelated `VAR=value` token. Separately it blocks --tier full|limited but allows native|slow|opt, which are equally long."
status: done
owner: agent-AN
---

# The no-full-suite hook refuses a dry run, and lets half the long tiers through

- **Type:** bug (agent tooling) — **Track A** (owns `.claude/**`; the hook
  landed as `1d0e227a8 chore(A)`).
  Found by Track T while checking the hook against its own workflow, at the
  user's request. **T owns the tool, never the bug** — reported, not edited.
- **Found:** 2026-08-13, hours after the hook landed.

**The hook is a good idea and it works.** Verified against the whole Track T
command set: `--tier quick`, `--pin`, `gate.sh quick`, `make compiler/pascal26`,
`make lib-test` and `make demos` all pass; `make test*`, `gate.sh full|limited`
and `--tier full|limited` are refused; both escape hatches work, including the
inline `PXX_TRACK=T <cmd>` form. The watcher daemon is untouched, as it must be
— it is a systemd unit, so no Claude Code hook ever sees it (confirmed: it
published native, opt and slow tiers after the hook landed). Two defects only.

## 1. `make -n` is refused, and it is a DRY RUN

```
DENY   make -n test-nilpy
DENY   make -n --no-print-directory test
```

`make -n` prints the recipe and executes **nothing**. Measured cost on this
repo: **0.08 s**. It is not a regression suite by any definition the hook's own
comment offers ("the same ten minutes wearing a different hat" — there are no
minutes here).

It is also load-bearing:

- `tools/testmgr.py`'s `make_dry_run()` builds the entire job list from
  `make -n <target>`. That call is inside Python so the hook does not intercept
  it — but an agent debugging job splitting reaches for the same command by
  hand, and gets refused.
- The verification protocol now recommended in
  [[chore-makefile-testtmp-parameterize]] is a `make -n` capture across all 90
  targets, diffed before and after the sweep. That is the cheapest proof in the
  repo that a mechanical change is behaviour-preserving, and the hook refuses
  the next agent who follows the ticket.

### It is also bypassable by accident, which makes the rule leaky

```
DENY   make -n --no-print-directory test
ALLOW  make -n --no-print-directory PXX_TMP=/tmp/PINNED test-nilpy
```

Same command, same effect, different verdict. The regex is
`make[[:space:]]+(-[^[:space:]]+[[:space:]]+)*(test|check)…` — it allows a run
of `-flag ` tokens and then requires the target, so any `VAR=value` between
them breaks the match. A rule that a stray make variable defeats will be
defeated by accident before it is defeated on purpose.

**Fix:** exempt dry runs explicitly — `-n`, `--dry-run`, `--just-print`,
`--recon` — and let the `VAR=value` form fall through the same exemption
rather than through a gap.

## 2. It blocks two long tiers and allows three others

```
DENY   testmgr.py --tier full        DENY   testmgr.py --tier limited
ALLOW  testmgr.py --tier native      ALLOW  testmgr.py --tier slow
ALLOW  testmgr.py --tier opt
```

The pattern is `--tier[[:space:]]+(full|limited)`. But `native` is what the
watcher runs continuously, `slow` exists precisely because it holds
`test-uforth#blocktest` (**594 s in one job**), and `opt` is the optdiff sweep.
Any of the three costs a non-T lane the ten minutes the hook was written to
prevent.

This is convenient for Track T and wrong for everyone else. Either the tier
list should be "everything except `quick`", or the rule should key on something
other than an enumeration that has to be maintained as tiers are added — the
`slow` tier was created **today**, which is exactly how such a list goes stale.

## Not a defect, but worth knowing

**Track T's exemption is opt-in and no session sets it.** `PXX_TRACK` is unset
in a normal Track T agent session, so T meets a refusal on its own documented
gate (`--tier full`) and learns the hatch from the refusal text. That is
self-documenting and arguably correct — an explicit opt-in beats a lane
auto-detected from something forgeable. Flagged only so it is a decision rather
than a surprise; **a scheduled/autonomous T worker must export `PXX_TRACK=T`**,
because it has no human to read the refusal and could silently skip its gate
instead.

## Gate

`.claude/hooks/no-full-suite.sh` is not on any suite's path, so the gate is the
table above re-run: feed representative commands to the hook on stdin as
`{"tool_input":{"command":"…"}}` and check the verdicts. Include `make -n` in
both the bare and `VAR=value` forms, and every tier name `testmgr.py --list-tiers`
knows about.

## Resolution (2026-08-15)

Both defects fixed, plus one more of the same shape found while testing.

**1. Dry runs are exempt — by REMOVING them from the scanned text, not by
exiting early.** `-n`, `--dry-run`, `--just-print`, `--recon`, and the clustered
short form (`-kn`, `-j8 -n`). The obvious implementation — exit 0 the moment a
dry run appears anywhere — would have waved through `make -n test && make
test-nilpy`, which is one dry run and one suite. So the command is split on the
shell separators and the dry-run segments are dropped; the rules then scan
what is left. Splitting is coarse (a `|` inside a quoted string over-splits) but
that can only ever expose MORE text to the rules, never less.

*The bug in the first cut of this, since it is a good trap:* the surviving
segments were rejoined with `;`. Every rule ends its match with
`([[:space:]]|$)`, so `make test;` matched nothing and the hook allowed the exact
command it exists to refuse — caught only because the verdict table was re-run
rather than eyeballed. grep is line-oriented; the segments stay on their own
lines.

**2. `VAR=value` no longer breaks the target match.** The pre-target token run
now accepts `-flag` and `NAME=value` alike, in both the `test|check` rule and
the `stabilize` rule (which had the identical hole and nobody had tried it).

**3. Tiers are "everything except `quick`".** The enumeration `full|limited` had
allowed `native`, `slow` and `opt` — and `slow` exists precisely to hold
`test-uforth#blocktest` at 594 s in one job. Keying on the exception rather than
on a list means a tier added tomorrow is refused by default, which is the right
default for a rule about time.

**4. Found while testing: the read-only-first-word escape did not survive a
CHAIN.** `echo 'make -n' && make test` was allowed because the first word was
`echo`. It now requires a single command — with `git` deliberately keeping its
exemption through a chain, because a commit MESSAGE routinely contains both a
semicolon and a quoted command, and refusing that is the noisy false positive
that block was written to stop. A pipe stays fine either way.

### Gate

The ticket's own table, re-run against the hook on stdin (37 commands, verdicts
in the resolution commit). Every row is as specified: all four dry-run spellings
and the `VAR=value` form allowed; the two chained forms refused; `make test`,
`check`, `stabilize` (bare and with a variable), `gate.sh full|limited`, all
five non-quick tiers, bare `--pin` and the test-glob loop refused;
`lib-test`, `demos`, `compiler/pascal26`, `pin`, `stabilize-fast`, `gate.sh
quick`, `--tier quick`, `--pin --tier quick`, the grep/commit mentions and a
single named test allowed.

### Left as the ticket describes it

Track T's exemption stays OPT-IN. The ticket argues that is correct — an
explicit opt-in beats a lane auto-detected from something forgeable — and the
refusal text names the hatch, so a supervised T session learns it on contact. A
scheduled T worker must export `PXX_TRACK=T`; that belongs in the worker's own
setup, not in the hook.

## Log
- 2026-08-15 — resolved, commit PENDING-COMMIT.
