---
track: U
prio: 45
type: decide
blocked-by: []
summary: "MOOT 2026-08-31, not ruled on its merits. The owner is retiring fuzzing: 'i think we can stop fuzzing in general. i think we found all that csmith is able to discover by now. so that makes the hook question irrelevant.' The hook existed to stop agents pattern-killing each other's csmith batches; with no batches there is nothing to protect. Layers 1 and 3 stay landed and keep their value (docs no longer teach pkill -9 -f, tools/whokilled.sh still answers what killed a job). Worth recording that the hook was never evidence-backed either: pattern-pkill was NEVER OBSERVED -- kernel OOM and systemd-oomd were excluded, and peer SIGKILL survived as the hypothesis precisely because it leaves no trace. SCOPE SETTLED same day: csmith AND pasmith both stop -- 'we can stop fuzzing for now, our backlog big enough already. yet keep the oracle tooling, obviously.' Generators stop, ORACLES STAY (pydiff.py, gcc_diff_probe.sh, fpc_diff_probe.sh). Stopped for BACKLOG CAPACITY, not because the tools are bad -- restartable."
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

---

# MOOT 2026-08-31 — the activity it protects is being retired

Owner: *"to be fair, i think we can stop fuzzing in general. i think we found all
that csmith is able to discover by now. so that makes the hook question
irrelevant."*

Closed as **moot, not ruled**. If fuzzing ever returns, the analysis below is
still good and the fork is still open.

## What survives, and it is most of the value

Layers 1 and 3 landed and keep their value with or without a hook:
`debugging-playbook.md` no longer teaches `pkill -9 -f <path>`, `csmith_fuzz.py`
stamps a unique `--run-tag`, and `tools/whokilled.sh` answers what killed a job.
Only the refusal surface is dropped.

## The hook was never evidence-backed, which is worth recording

**Pattern-pkill was never observed.** Kernel OOM and systemd-oomd were excluded
on evidence; a peer's SIGKILL survived as the hypothesis *precisely because it is
the one that leaves no trace*. It would have guarded a plausible, undiagnosed
mechanism whose detector had just been built and never fired.

Cost side, measured the same day and then again while closing this ticket: the
sibling hook `no-full-suite.sh` refused a **read-only `grep` counting which NilPy
tests use `random`** — twice, mid-investigation — and then refused the **commit
message for this very ticket**, because the prose describing those refusals
contained the glob. Three false positives in one session, zero true positives,
and the third fired on a document rather than an action. That is the shape this
hook would have added more of.

## SCOPE NOT SETTLED — do not over-read this

The stated reasoning is **csmith-specific** (*"all that csmith is able to
discover"*). Three things could be meant and only the first is clearly covered:

1. **csmith** — random C program generation. Covered.
2. **The Pascal source mutator** (`fuzz.sh`) — a different generator with a
   different exhaustion argument; not covered by csmith's evidence.
3. **The differential probes** — `pydiff.py`, `gcc_diff_probe.sh`,
   `fpc_diff_probe.sh`. **Oracles, not fuzzers.** They compare our output against
   a reference on deliberately written programs. Retiring them would remove the
   instrument this repo's debugging discipline rests on. Nothing here touches
   them.

**ANSWERED the same day.** Owner: *"same applies to pasmith. we can stop fuzzing
for now, our backlog big enough already. yet keep the oracle tooling,
obviously."*

- **(1) csmith and (2) pasmith: STOP.** Both generators.
- **(3) the differential probes: KEEP.** Explicitly and obviously.

**The stated reason is capacity, not quality** — *"our backlog big enough
already"*. That matters for how this is carried out: the generators are being
paused because their findings outrun the queue, not because they were wrong. So
**pause them, do not delete them.** Leave `csmith_fuzz.py`, the pasmith tooling
and their run tags in the tree; stop scheduling batches. The word is "for now".

The distinction to hold on to: a **generator** invents programs, a **probe**
compares our answer to a reference on a program someone wrote. The backlog
argument applies to the first and never to the second.

*Closed 2026-08-31 as moot by the owner's retirement of the activity.*
