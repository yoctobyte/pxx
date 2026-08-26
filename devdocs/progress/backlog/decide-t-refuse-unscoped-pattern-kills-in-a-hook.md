---
track: U
prio: 45
type: decide
blocked-by: []
summary: "Layer 2 of the pattern-pkill ticket is a PreToolUse hook refusing `pkill -f <toolname>` / `killall` with a bare pattern. It is a .claude/ config change binding every agent on this box, so it is the owner's call, not a track agent's or a peer's. Layers 1 and 3 landed without it; this is the only part left."
---

# Should a hook refuse unscoped pattern kills?

- **Track U** (decision) — raised by Track T on 2026-08-26, out of
  [[bug-t-agents-kill-each-others-processes-with-pattern-pkill]].
- **Why it is here and not just done:** the mechanism is `.claude/hooks/` +
  `.claude/settings.json`, which binds **every agent on this box, in every
  session**, including future ones that never see this ticket. CLAUDE.md and the
  cross-session rules both say config of that kind is not a track agent's to
  change and not a peer's to authorise. So it is filed rather than guessed —
  escalate, don't guess.

## The fork

`pkill -f csmith_fuzz.py` asks *"is there a process whose command line contains
this text?"* when the question is *"is there a process **I** started?"*. Those
coincide exactly while one agent runs a tool and diverge silently the moment two
do. Two csmith batches died mid-run this way (hypothesised — see below).

**Should the repo refuse the dangerous form mechanically, the way
`no-full-suite.sh` refuses a full suite?**

## What is already true, so the decision is only about the hook

- **Docs fixed.** `debugging-playbook.md` no longer teaches `pkill -9 -f <path>`;
  it leads with the fresh-output-path fix and makes a *scoped* kill the fallback.
- **Tools stamped.** `csmith_fuzz.py` puts a unique `--run-tag` in its own
  command line, so a scoped pattern kill is now possible at all.
- **A diagnostic exists.** `tools/whokilled.sh` answers what killed a job.
- **The cause is narrowed but not proven.** Kernel OOM and systemd-oomd are both
  excluded on evidence; a peer's SIGKILL is the surviving hypothesis precisely
  because it is the one that leaves no trace. **Pattern-pkill has still never
  been observed.** So this hook is defence against a mechanism that is plausible
  and cheap to prevent, not against a diagnosed one — worth saying plainly,
  because it changes how much friction is worth paying.

## Options

**A. Adopt the hook.** Refuse `pkill`/`killall` with a bare name pattern; allow
`kill <pid>`, `pkill -f` with a run tag, and anything scoped to the agent's own
workdir. Print the positive pattern in the refusal so it teaches rather than only
blocks — the shape that made `no-full-suite.sh` work.
*Cost:* one more thing between an agent and a legitimate action; false positives
land on whoever is debugging at the time, which is the worst moment to be
blocked. `no-full-suite.sh` already produced one false positive this week (a
`for f in test/...` loop that was not a suite run).

**B. Docs + tags only — what is already landed.** No new refusal surface.
*Cost:* it relies on agents reading the playbook, and the playbook had taught the
opposite for months without anyone noticing.

**C. Warn, don't refuse.** Hook prints the scoped form and lets the command
through.
*Cost:* a warning nobody must act on is one nobody reads; but it costs nothing
when it is wrong, which matters for a mechanism that is still hypothetical.

## Recommendation

**C, and revisit at A if it recurs.** The cause is unproven, the two landed
layers remove both the bad instruction and the excuse for it, and a hard refusal
buys certainty against a hypothesis at the price of friction during debugging —
which is when agents are least able to absorb it. A warning that names the run
tag turns the moment of the mistake into the moment of the lesson, and
`whokilled.sh` means a recurrence gets diagnosed in one command rather than
re-litigated. If a second incident lands with a warning already in place, that is
the evidence that justifies A.

## Log
- 2026-08-26 — filed by Track T; layers 1 and 3 landed, layer 2 escalated here.
