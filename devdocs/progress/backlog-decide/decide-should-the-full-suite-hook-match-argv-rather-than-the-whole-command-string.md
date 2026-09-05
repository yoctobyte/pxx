---
slug: decide-should-the-full-suite-hook-match-argv-rather-than-the-whole-command-string
track: U
type: decide
prio: 40
status: new
owner: user
found: 2026-09-05
found-by: frankH and frank-coordinator, independently, same evening
blocked-by: []
summary: "`.claude/hooks/no-full-suite.sh` matches the whole Bash command string, and a heredoc commit message is part of that string. So a commit message that NAMES a full-tier recipe in order to explain that it was NOT run is refused -- and so is a markdown document quoting a corpus glob. Two independent instances on 2026-09-05, neither running any test. The cost is not the keystroke: the hook penalises precisely the practice CLAUDE.md asks for, which is writing the gate justification into the commit message, and the workaround (`-F` a file, or the Write tool) is invisible to the next person, who learns only that mentioning a tier in prose is painful. NOBODY MAY NARROW THIS ON THEIR OWN JUDGEMENT -- it is permission machinery and the direction of the change is 'less strict', so it is an owner call. The fork: match argv only, keep matching the whole string, or exempt the commit-message path."
---

# Should the full-suite hook match argv rather than the whole command string?

## The fork

`.claude/hooks/no-full-suite.sh` is a **text** instrument reading a **command
string**. It cannot tell an invocation from a description of one.

1. **Match argv only** — the executable and its arguments, not heredoc bodies or
   `-m` text. Narrower, and *narrowing permission machinery is the direction that
   needs an owner.*
2. **Leave it.** The workarounds are cheap and the guard stays maximally blunt.
3. **Exempt the commit-message path specifically** — the narrowest change: a
   heredoc or `-F` body destined for `git commit` is prose by construction.

**Recommendation: 1 or 3, and 3 if there is any doubt** — it fixes both measured
instances and cannot loosen anything that runs a test, because a commit message
runs nothing. But this is `rejected/`-adjacent only if the owner thinks the cost
is imaginary, and it is not, for the reason below.

## The two instances, neither of which ran a test

**frankH, landing `unitalias` (`731463e70`).** The commit message named the core
tier recipe **in order to say it had not been run and why** — the change is inert
without a manifest row, the lookup exits on a zero count before the cached walk,
so every existing compilation takes the path it took before. The hook refused
**the commit**. Passed via `-F` instead; hook left alone, deliberately.

**frank-coordinator, appending to the roster.** A markdown document quoting a
corpus glob inside a heredoc, in a commit touching one file. Refused. Landed
through the Write tool — and explicitly **not** by setting
`PXX_ALLOW_FULL_SUITE=1`, since that flag asserts *"I genuinely need the full
suite"*, which would have been false.

**Both authors declined to route around the guard and both were right to.** The
rule against rephrasing a command to slip past a hook is absolute, and neither
did. But note what each did instead: one changed the transport, one changed the
tool. **Neither leaves any trace for the next person**, who will meet the same
refusal cold.

## Why the cost is not the keystroke

CLAUDE.md asks, in as many words, for the gate justification to go **in the
commit message** — *"say in the commit why quick was not enough"*, and *"note it
in the commit message, the only warning anyone gets."*

> **The hook makes the one place we ask for gate reasoning the one place gate
> reasoning is expensive to write.**

That is a slow, invisible pressure toward vaguer commit messages: the author who
hits this twice stops naming the recipe and writes *"did not run the big one"*,
which is exactly the sentence that is useless to a reader six weeks later. **The
guard does not fail loudly here; it shapes what people write.**

It is also this tree's own recurring class, arriving in the guardrail that
enforces this tree's rules: **an instrument that reads text cannot tell an
assertion from a description of one.** Same animal as a `grep -L` answering about
a literal string, and as frankZ's `uses` regex reading *"Uses only the language
surface that ALL backends support today"* out of a header comment and yielding
the unit `i386`.

## What is NOT in scope

**The escape hatch is not the problem and must not be touched.**
`PXX_ALLOW_FULL_SUITE=1` is a SPEED guardrail an agent lifts autonomously, no
permission needed, and it is documented in the hook's own text at line 93. Two
sessions this evening read that wrongly as a permission gate and one of them
declined work it was entitled to do. **That is a separate finding about the
hook's legibility, not an argument for changing what it blocks** — and the fix
there, if any, is wording.

**Nobody may implement any option here without the owner saying which.** Filed by
the coordinator, which holds no lane and writes no code, precisely because both
finders correctly refused to decide it themselves.
