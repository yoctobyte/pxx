---
track: U
prio: 40
type: decide
blocked-by: []
summary: "no-full-suite.sh matches command TEXT, so a `git commit` whose MESSAGE explains why test-nilpy is full-tier-only is refused as an attempt to run it — killing the whole command line including the `git add`. Five instances now, four of them landing on a document ABOUT the tier split. Any fix edits .claude/hooks/, which binds every agent on this box, so it is the owner's call."
---

# Should the full-suite hook stop matching prose about the suite?

- **Track U** (decision) — raised by Track T on 2026-08-30, from a Track O
  session's report; sibling of
  [[decide-t-refuse-unscoped-pattern-kills-in-a-hook]].
- **Why it is filed and not just done:** the mechanism is
  `.claude/hooks/no-full-suite.sh` + `.claude/settings.json`, which binds
  **every agent on this box, in every session**. CLAUDE.md says config of that
  kind is not a track agent's to change and not a peer's to authorise, and this
  report came from a peer. Escalate, don't guess.

## What happens

`.claude/hooks/no-full-suite.sh` pattern-matches the **text** of a Bash
command. A commit whose *message* contains the words `make test-nilpy` — as
prose, explaining why that suite is full-tier only — matches, and the refusal
kills the entire command line, so a bundled `git add` never runs either. It
surfaces as an error, not a warning, and the refusal text talks about
regression suites while the author is writing a commit message.

## The count, because it is the argument

Five instances across four sessions, and **four of the five landed on a
document about the tier split** — a ticket body quoting `optdiff.sh`'s file
list, a commit message explaining why the nilpy suite is full-tier only, and
so on. That is the selection effect that makes it worth a decision rather than
a shrug: the false positive is aimed almost exactly at the people writing down
*why the rule exists*, which is the writing you least want discouraged.

The workaround is trivial and known — rephrase to "the test-nilpy suite" — and
every reporter so far has found it within one rewrite.

## The fork

1. **Leave it.** The hook is doing its job; the false-positive rate is low; the
   workaround costs one rewrite. Every rule that inspects text will have edge
   cases, and loosening a guard to accommodate prose is how guards die. This is
   what the reporting Track O session recommended, and what the pattern-kill
   ticket's own history suggests: a slightly over-eager refusal has been
   cheaper than a missed one.
2. **Scope the match to the command being RUN.** Skip the check for text inside
   a `-m`/`-F` argument or a heredoc body — i.e. match the words only where
   they could execute. Narrow and mechanical, but it is a real parser for shell
   quoting inside a hook, and a wrong one re-opens the hole it guards.
3. **Downgrade to a warning for a `git commit`.** Keep the refusal everywhere
   else; when the matched command is a commit, print the warning and allow it.
   Cheapest of the three and it preserves the `git add`, at the cost of one
   allowed shape that a determined caller could abuse — though a caller who
   wants the suite would just run it directly, which is still refused.

## Recommendation

**Option 1 (leave it), unless the owner is bothered by the selection effect** —
in which case option 3, which is a two-line change and removes the sharpest
edge (the lost `git add`) without teaching the hook to parse shell quoting.
Option 2 buys the most correctness and costs the most risk, and the thing being
protected is not worth a quoting parser.

Track T holds no opinion strong enough to act on unilaterally; this is recorded
so the fifth instance is the last one that has to be rediscovered.
