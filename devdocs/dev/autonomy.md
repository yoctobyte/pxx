# Autonomy: grind unattended, steer occasionally

The goal of this note is a working equilibrium: **pxx keeps progressing without
consuming the maintainer's attention.** Agents carry the verifiable queue 24/7;
the human steers with a light touch — curating priorities and answering the
decisions that agents must not guess. This is the answer to two competing worries
at once ("I'm spending too much time on it" and "I shouldn't tunnel-vision one
project"): make the project advance *while you're not looking*, and both dissolve.

It is deliberately **not** "an agent replaces the maintainer." Agents are
excellent at *verifiable grind* (cross-target reds, fuzzing, library compat, the
mechanical parts of a feature) and unreliable at *judgment forks* (is this
behaviour intended? which design? is this finding real?). The split below is
built around exactly that line.

## Track U — User: the decision lane

Formalise what the `decide-*` tickets already imply. **Track U is where human
judgment lives.** It is not a file-lane — it owns no source, has no gate, builds
nothing. It is the **escalation target**.

- **The rule for autonomous agents: escalate, don't guess.** When an agent hits a
  fork it cannot resolve from the code, the request, or a sensible default — a
  design choice, an "is this intended vs a bug?" question, a spec ambiguity, a
  wording/semantics call — it **files a Track U ticket and moves on to the next
  queue item.** It does not burn cycles guessing, and it does not silently pick a
  direction that might be wrong. (This session had three such forks: the fuzzer
  divergence that turned out to be impl-defined, the eliah crash whose fix hinged
  on "the `{$I+}` flip was intentional", and the RTTI opt-out design. Each is a
  textbook Track U item.)
- **The human works Track U to steer.** Clearing the decision queue *is* the
  steering — you rate goals and resolve forks; the autonomous lanes unblock and
  grind on. One decision often unblocks a chain (prio propagates down dep edges,
  so a resolved `decide-*` can release a whole ranked sub-queue).
- **Slug convention:** `decide-<topic>` (already in use). A Track U ticket states
  the fork, the options, the trade-offs, and — if the agent has one — a
  recommendation, so the human can answer in seconds. Same shape as a good
  `AskUserQuestion`, persisted.
- **Escape rule (mirror of the X/compat rules):** a Track U item that turns out to
  be a plain bug or a mechanical task once decided is re-filed into the owning
  lane. U holds *open questions*, not work.

## The autonomous loop (per lane)

Each staffed lane runs the documented cold-start loop (see the top-level
`CLAUDE.md` "continue on tickets"):

```
pull --rebase
next --track <X>          # highest effective-prio ready ticket in the lane
claim <slug> <agent-id>
  ... do the work ...
land green                # the lane's gate: A = make test + self-host byte-identical;
                          # B = lib-test/demos; C/Z = tests + self-host + cross; etc.
resolve <slug> <commit>
board-md ; commit the move ; push
loop
```

Two hard guardrails make this safe to run unattended:

1. **Land only green.** The gates already exist (self-host fixedpoint, quick tier,
   the pin boundary, push-your-own-lane). An agent that can't get green **reverts
   or parks to `unfinished/` and files a Track U/A ticket** — it never pushes a
   broken or half-refactored state. A Track A ticket parked in `unfinished/` is
   critical (it can break the stable-binary gate) and `progress.sh check` fails
   until resolved — that failure is itself a signal to the human.
2. **Escalate, don't guess** (Track U, above).

Track T's watcher already embodies this for testing/fuzzing: it runs 24/7 in its
own clone, tests every SHA, fuzzes spare cycles, and files regression tickets into
the owning lane. The autonomy plan is to generalise that daemon shape to a
**worker agent per lane**.

## The schedule

Run the loops as scheduled cloud agents (`/schedule` → cron routines) and/or
`/loop`. Suggested shape — tune cadence to how much you want landing per day:

| lane | what the routine does | cadence | notes |
| --- | --- | --- | --- |
| **A+** (core, usually combined) | top ticket: IR/backend/ABI/self-host/opt; most work lands here | daily / nightly | sole-A guard: only one A worker at a time (self-host gate is serial) |
| **B** (libs/demos) | lib compat, demo fixes, `lib-test`/`demos` dashboard | daily | builds on `pinned`, never rebuilds the compiler — cheap, parallel-safe with A |
| **C / Z / R** (frontends) | corpus expansion, frontend long-tails | a few times/week | disjoint files → safe alongside A; shared-internals change → files a Track A ticket |
| **T** (watcher) | already live: test matrix + fuzz + file regressions | continuous | the reference daemon; keep it running |
| **U** (decisions) | **human**, not scheduled | your cadence (e.g. weekly) | clearing U is the steering act |

Most autonomous throughput is **A+** — the maintainer confirmed the bulk of the
backlog lands under A (or A-tagged O/E work). B and the frontends fill spare
parallel capacity. **Only one agent holds A at a time** (the self-host
byte-identical gate is serialising); B/C/Z/R workers run alongside freely because
their files are disjoint.

## The human review cadence

The whole point is that this is **small and infrequent**:

1. **Clear Track U** — answer the `decide-*` forks. This is the steering; it's
   also the highest-leverage thing you do (one answer unblocks a chain).
2. **Skim what landed** — the board + recent commits. tstate/the watcher surfaces
   regressions tied to exact SHAs, so you don't re-verify; you spot-check.
3. **Re-prioritise the backlog** — bump/lower `prio:` on goals. Because prio
   propagates down dependency edges, rating the *goals* re-ranks the whole queue;
   you never hand-order tasks.

Timebox your own involvement (e.g. one review+steer session a week). The agents
carry the grind between sessions; nothing you defer gets harder.

## Tooling & model notes

- **Single agent tool: Claude Code.** Consolidating on one toolchain (vs juggling
  several) is itself a simplification — one gate model, one ticket system, one set
  of guardrails. Tested against the one serious alternative; the tooling
  (queue/gates/watcher integration) proved the differentiator, not raw model IQ.
- **Model tier rarely the bottleneck.** Opus 4.8 for the substantive work
  (design, codegen, debugging judgment). Sonnet 5 is adequate for *simple /
  mechanical* tickets (rote edits, corpus runs) — cheaper to grind. Fable 5 is
  nice-to-have, not required. The scarce resource is *good tickets and clear
  decisions*, not model capability — which is why Track U and backlog curation are
  the leverage points, not the model dropdown.

## What this is not

- Not unattended *design*. Direction, semantics, and "is this right?" stay with the
  human (Track U). Agents that try to decide these drift — see the judgment forks
  above.
- Not a licence to skip gates. Unattended only works *because* the gates are hard
  and the escalation rule is followed. Loosen either and quality rots silently.
