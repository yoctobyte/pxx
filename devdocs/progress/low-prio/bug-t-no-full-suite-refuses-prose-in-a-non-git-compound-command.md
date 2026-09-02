---
slug: bug-t-no-full-suite-refuses-prose-in-a-non-git-compound-command
track: T
prio: 65
type: bug
blocked-by: []
summary: "no-full-suite.sh matches on command TEXT, and its read-only first-word exemption is blanked by any `&&` unless the first word is literally `git`. So `printf '...glob...' >> LOGBOOK.md && git add && git commit` is refused for PROSE naming a suite, never for running one. Three sessions hit it independently in one night (frankZ 04:24, frankB twice, once via `pgrep -af \"gate.sh full\"` matching its own command text)."
status: low-prio
---

# T: the prose false positive survives, in the chain rule rather than the word list

The hook already knows about this failure class — its own comment says "READING
ABOUT a rule is not running it", and it exempts read-only first words plus `git`
through a chain, precisely because a commit message routinely quotes a forbidden
command. Both exemptions are correct. The gap is where they meet.

`case "$cmd" in *"&&"*|*"||"*|*";"*) [ "$first" = git ] || first='' ;; esac`
blanks the read-only exemption for every compound command that does not START
with `git`. The canonical agent commit does not:

    printf '%s\n' '... test/c_crtl_*.c ...' >> devdocs/progress/LOGBOOK.md \
      && git add ... && git commit -F - <<'MSG' ... MSG

`first` is `printf`, the chain rule blanks it, and the glob inside the LOGBOOK
prose then matches. Nothing in that command can start a suite.

## Measured, one night, three sessions independently

- **frankZ, 04:24** — LOGBOOK text containing `test/c_crtl_*.c`. Reworded,
  pushed as `67cf9588a` / `7807facef`.
- **frankB, x2** — commit-message prose containing `make test`; and separately
  `pgrep -af "gate.sh full"`, where the command matched **its own argument** —
  a process *query* refused for naming what it queries.

## Why it is worth fixing rather than rewording around

1. **It taxes the logbook.** The rule that produced all three hits is "log one
   line in LOGBOOK.md saying WHAT AND WHY". A line that names the glob it is
   about is the most useful kind, and it is the kind that gets refused.
2. **The refusal takes the whole compound command.** PreToolUse means nothing
   runs, which is the safe direction — but the agent must VERIFY that rather
   than assume it. frankZ checked; the cost of the class is that it is checkable
   only by hand.
3. **It trains the wrong reflex.** Three agents rephrased to get past a guard
   that was right about the shape and wrong about the command. Next time the
   guard is right about both, the reflex is already "reword it".

## Recommended direction (T's call, not filed as a decision)

Match on the command with quoted strings and heredoc bodies **removed**, rather
than widening the word list or the chain exemption. That addresses all three
instances and the `pgrep` self-match at once, because every one of them is a
forbidden string inside a quote. Widening the chain rule to keep the read-only
exemption would fix frankZ's and frankB's commit case but not `pgrep`.

**Positive control this needs:** a compound command that genuinely DOES start a
suite after a read-only first word — `echo 'noop' && make test` — must still be
refused. The hook's own comments record that exact bypass being found and closed
once; any fix here must not reopen it.

## Not in scope

`PXX_ALLOW_FULL_SUITE=1` is not the answer. It is a speed guardrail with an
autonomous escape, and using the escape to post a logbook line teaches agents to
reach for it when the hook is merely wrong, which is the one habit that makes
the guardrail stop working.

## Deprioritised 2026-09-02 — the Track T tooling backlog was cut as a pile

**This ticket is not being called wrong.** It was moved as part of a pile, not
judged individually, and nothing here disputes its finding.

Owner decision. 73 of the 74 open `track: T` tickets were filed between
2026-08-31 and 2026-09-02, 58 on one day. The pile was too large to work through
and returned almost nothing, and a ticket nobody will fix does not sit neutrally
— it stays in the ranker forever at zero value, which is the argument CLAUDE.md
already makes for a terminal folder over a low prio.

Four were kept in the ranker on a purely structural test — an active umbrella or
a hard `blocked-by:` edge from live work:
`umbrella-one-full-tier-run-with-no-red-tier`,
`feature-t-freebsd-image-and-runner`, and the two `regression-test-core-*` reds
that block the umbrella.

**Kept, not deleted, for two reasons:** so the finding is not rediscovered and
refiled from scratch by the next agent who trips over it, and so it can be pulled
back if what it touches becomes load-bearing.

**To revive it:** move it to the owning lane's backlog, set `status: backlog`,
and say in the ticket WHAT CHANGED to make it matter now. Restoring it because it
reads well is how the pile comes back.
