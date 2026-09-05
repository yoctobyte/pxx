---
slug: bug-t-the-full-suite-hook-refuses-writing-about-the-suite-not-just-running-it
track: T
prio: 35
type: bug
blocked-by: []
status: backlog
found: 2026-09-05
found-by: frankC
owner: unassigned
summary: "`.claude/hooks/no-full-suite.sh` matches the COMMAND TEXT, so it refuses commands that merely CONTAIN a suite name in prose rather than invoking one. Three refusals in one session, none of them a suite run: a heredoc writing a ticket whose body said `gate.sh full`, a logbook line naming a `test/` glob, and a `git commit -F -` whose MESSAGE said `make test` while explaining why the quick tier was enough. Each cost a retry through a different tool. The guard is right and must stay; it is the aperture that is wrong — it cannot tell `make test` from a commit message about `make test`."
---

# The full-suite hook refuses WRITING about the suite, not just running it

## What happened

Three refusals in one session, none of which ran anything:

1. A `cat > ticket.md <<'EOF'` heredoc whose ticket body contained the words
   `gate.sh full` while explaining that the wide gate was red.
2. A `cat >> LOGBOOK.md` heredoc whose log line listed the tests added as a
   `test/` glob.
3. `git commit -F -` with a heredoc message containing `make test`, in a
   sentence explaining **why the quick tier was sufficient** — the exact
   justification the hook's own refusal text asks authors to write.

Each was worked around with a different tool (`Write` for the files, a message
file for the commit), so nothing was lost but time. The third is the sharpest:
the hook demands you "say in the commit why the quick tier was not enough", and
then refuses the commit for saying it.

## Why this is not a request to weaken the guard

The guard is doing real work and the refusal text is correct about the policy.
`PXX_ALLOW_FULL_SUITE=1` exists and is lift-it-yourself, and I used it
autonomously and legitimately in the same session for a two-backend
calling-convention change. **Do not fix this by loosening what counts as a
suite invocation, and do not fix it by teaching agents to rephrase prose so it
slips past** — a guard you route around is a guard the owner no longer has.

## The aperture

The hook reads the command STRING. A command that WRITES a file whose CONTENT
mentions a suite is not a suite invocation, and the two are distinguishable:
the suite name appears inside heredoc body lines, or after `-m`/`-F`, rather
than in command position.

Cheapest honest fix is probably to ignore heredoc bodies (between `<<'EOF'` and
the terminator) and `git commit` message arguments when scanning, leaving
command-position matching exactly as it is. That keeps every real invocation
refused and stops the false positives.

**Check the positive control after any change**: a real `make test` inside a
heredoc-writing command must STILL be refused if it is in command position, and
`PXX_ALLOW_FULL_SUITE=1 make test` must still be allowed. A fix that makes the
hook stop refusing anything is the failure mode here.

## A fourth instance, while filing this

The commit that first tried to land THIS TICKET was refused, for a message
describing the refusals. That is the cleanest possible statement of the
aperture problem: the hook cannot distinguish a suite invocation from a
document about suite invocations, including the document filed to report that
it cannot. Landed via a message file instead.

## Cost

Low but recurring, and it lands on exactly the agents doing the right thing —
writing down why they did or did not widen their gate. It also mildly
discourages naming the suite in a commit message, which is the one place that
information is useful later.
