---
prio: 60
track: T
status: done
---

# bug(T): the full-suite hook keys on the TIER NAME, so it refuses the repro line every auto-filed regression ticket prints

`.claude/hooks/no-full-suite.sh:118-120` matches `testmgr\.py.*--tier[[:space:]]+[a-z]+`
and exempts only `--tier quick`. It has **no aperture for `--job`**, which
narrows a tier to a single case — so `tools/testmgr.py --tier native --job
'test-core#src:...'`, a ~0.5s run of exactly one test, is refused with the text
*"every testmgr tier except quick is Track T's sweep — native, slow and opt cost
the same ten minutes as full and limited."* That sentence is true of the tier and
false of the command.

## Why it matters more than a one-off annoyance

**Every auto-filed regression ticket prints this exact command as its `## Repro`.**
Measured 2026-09-03 by folder (not by a glob across all of them):

| folder | tickets carrying a `--job` repro |
| --- | --- |
| `backlog/` | **6 of 6** |
| `backlog-core/` | 0 of 142 |
| `backlog-tools/` | 0 of 8 |
| `working/` `unfinished/` `blocked/` `urgent/` | 0 |

`backlog/` is where twatch files regressions, so the population is not "some
tickets" — it is **the entire auto-filed regression population, 100%**. The
watcher writes a repro the repo then declines to run.

## The shape, which is the reason to fix it rather than route around it

The hook is a **speed** guardrail: its own header says so, and its refusal text
prints the hatch. It is aimed at ten-minute sweeps. But it decides by reading the
tier NAME, and a name is not a duration — `--job` changes the cost by three
orders of magnitude without changing the word the hook matches on. This is the
handbook's *"the name is not the thing"*: an instrument that does not error,
answers confidently, and is **correct about the tier while being asked about the
command**.

It is not dangerous, because the hatch works and Track T's own commit trail shows
agents lifting it correctly. What it costs is that the first thing an agent does
with a fresh regression ticket is get refused, and the refusal argues at length
that the command is expensive when it is not — so the agent must disbelieve a
specific, confident message to proceed. **A guardrail that is wrong in its
reasoning teaches agents to discount guardrails that are right.**

## Suggested fix

Exempt a command that carries `--job` (and, likely, `--only`/`--test` if those
exist) the same way `--tier quick` is exempted, at `no-full-suite.sh:118-120`.
Keep the tier refusal otherwise. **Add a positive control**: a `--tier native`
WITHOUT `--job` must still be refused, asserted — an exemption widened by hand is
exactly the kind that stops being able to fail.

## Provenance — the instrument caught itself

Filed by the coordinator after handing frankh-15 a verification command it then
could not run. The command was written from the ticket's own `## Repro` line and
never executed by its author; frankh-15 ran it under `PXX_ALLOW_FULL_SUITE=1`,
noted why in the commit (`4a0de8788`), and reported the refusal back. Two things
worth keeping from that: **a repro line copied out of a ticket is not a command
anyone has run**, and `quick` could not have substituted here — it does not
cover `test-core`'s native rows, so it would have returned GREEN on a job that
was RED.

Related, all open, none covering this: `decide-t-the-full-suite-hook-refuses-prose-about-the-suite`,
`bug-a-no-full-suite-hook-refuses-make-n-and-misses-half-the-long-tiers`,
`bug-t-no-full-suite-refuses-prose-in-a-non-git-compound-command`. **Four tickets
against one 200-line hook is the smell the handbook names** — count how many
mechanisms serve one concept. Whoever takes this should read all four before
editing, and consider whether the answer is a fifth patch or one rewrite that
decides on the ESTIMATED COST of the command rather than on the words in it.

## Log
- 2026-09-03 — resolved, commit wildcard-free --job aperture, plus the hook's first test wired into gate.sh quick.
