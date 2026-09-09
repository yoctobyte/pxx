---
track: U
prio: 55
type: decide
blocked-by: []
summary: "no-full-suite.sh matches command TEXT, so writing ABOUT a suite is refused as running one. RE-COUNTED 2026-09-06: at least TEN instances across five-plus sessions, not five -- two further Track T tickets were filed independently on 2026-09-05 reporting the same cause, which is itself the finding, since this row was written to stop exactly that rediscovery. AND THE COUNT CHANGES THE FORK: option 3 (downgrade for `git commit`) covers only a MINORITY of the measured instances -- three of frankC's five are `cat > file` / `cat >> LOGBOOK.md` heredocs that write FILES, and a separate rule (the shell-loop one) fires on the word `for` plus a `test/` glob inside a heredoc body, with a two-line repro. Every single instance is an author WRITING DOWN WHAT THEY DID, which is the sentence the hook's own refusal text instructs them to write. Any fix edits .claude/hooks/, which binds every agent on this box, so it is the owner's call and no agent may make it."
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

## RE-COUNTED AND RE-ARGUED 2026-09-06 (frank-coordinator) — the count doubled and it moves the recommendation

**This row said, in its own last line, that it was recorded "so the fifth instance is the
last one that has to be rediscovered."** On 2026-09-05, **two further Track T tickets were
filed independently** by two sessions reporting the same cause:

- `bug-t-the-full-suite-hook-refuses-writing-about-the-suite-not-just-running-it` (frankC)
- `bug-t-the-full-suite-hook-scans-heredoc-prose-and-refuses-documentation`

Both are now wired `blocked-by:` this row. **The rediscovery is not a filing error to tidy
away — it is evidence.** A decision recorded in `backlog-decide/` did not reach two sessions
that hit the defect a week later, so "it is written down" is not a cost the fork may count
as paid.

### The consolidated count

| source | instances | shapes |
| --- | --- | --- |
| this row, 2026-08-30 | 5 | four on documents ABOUT the tier split; a ticket body quoting `optdiff.sh`'s file list; a commit message on the nilpy tier |
| frankC's row, 2026-09-05 | 5 | `cat > ticket.md` heredoc containing `gate.sh full`; `cat >> LOGBOOK.md` naming a `test/` glob; `git commit -F -` whose message said `make test`; **the commit filing that ticket, refused for describing the refusals**; a logbook line recording a sweep that had been properly declared with `PXX_ALLOW_FULL_SUITE=1` |
| the heredoc row, 2026-09-05 | repro | rule 3 (shell-loop) firing on the word `for` plus a `test/` glob **inside a heredoc body** — quoting a Pascal `for i := 0 to n` is enough |

**At least ten, across five or more sessions, two of them self-referential:** the commit
filing the ticket about the hook was refused by the hook, and *the refusal text tells the
author to say in the commit why the quick tier was not enough — twice now that exact
sentence has been refused for containing the words it asks for.*

### Why the count changes the fork rather than just restating it

**Option 3 was the cheap arm and it does not cover the majority of the measured
instances.** Only two of frankC's five are `git commit`; **three are `cat >` / `cat >>`
heredocs writing FILES**, which option 3 leaves refused exactly as they are. And **it is not
one rule**: the shell-loop rule matches `for` + a `test/` glob independently of the suite-name
rule, so a fix aimed at `-m`/`-F` arguments does not reach it. The two-line repro in the
heredoc ticket is the cheapest way to see this.

**Option 1's cost estimate was five instances with a one-rewrite workaround.** The measured
cost is ten-plus, three duplicate tickets, and a workaround that **differs per tool** — the
`Write` tool for file content, a message file for `git commit -F`, and for the shell-loop
rule a rephrase of prose that the reporters explicitly refused to make. *Every reporter has
declined to reword the prose to slip past the guard, correctly, and CLAUDE.md says so in as
many words: a guard you route around is a guard the owner no longer has.*

**The selection effect is stronger than "aimed at people writing down why the rule
exists".** It is exact: **every one of the ten instances is an author writing down what they
did, and the hook's own refusal text instructs them to write it.** The false-positive
population is precisely the population the policy exists to create.

### What has NOT changed, and it is why this stays a decision

**No reporter asks for the guard to be weakened, and neither does this note.** frankC's row
states the constraint the fix must hold: *"do not fix this by loosening what counts as a
suite invocation, and do not fix it by teaching agents to rephrase prose so it slips past."*
`PXX_ALLOW_FULL_SUITE=1` is lift-it-yourself, is used autonomously and legitimately, and
must keep working. **The positive control any fix must pass is already written down:** a
real `make test` in command position inside a heredoc-writing command must STILL be refused,
and `PXX_ALLOW_FULL_SUITE=1 make test` must still be allowed. *A fix that makes the hook stop
refusing anything is the failure mode here.*

### Revised recommendation

**Option 2, scoped to heredoc bodies only** — skip the scan between `<<'EOF'` and its
terminator, leave `-m`/`-F` and command-position matching exactly as they are. It is the
arm this row rated most correct and most risky, and the risk assessment was made against a
population that has since changed: heredoc bodies are where the majority of measured
instances live, they have an unambiguous delimiter that needs no shell-quoting parser, and
skipping only them leaves every real invocation refused. **Option 3 is no longer the cheap
arm, because it fixes two of ten.** Option 1 remains coherent — the reporters have all
absorbed the cost and none is blocked — but it should be chosen against ten instances and a
failed recording, not against five and a shrug.

**Raised 40 -> 55** on the measured count, not on urgency: nobody is blocked, and the reason
to rank it is that a p40 decide row is what produced two duplicate filings.

**Nothing here touches `.claude/**`.** This row is prose about a decision that is the
owner's alone; no agent may edit the hook, the settings or CLAUDE.md, and a peer cannot
authorise it.

## AN ELEVENTH INSTANCE, 2026-09-06, AND IT HAPPENED TO THE SEAT CONSOLIDATING THIS ROW

Within an hour of writing the consolidation above, `frank-coordinator` was refused while
filing an unrelated Track T ticket. The command was a `cat > <ticket>.md <<'EOF'` heredoc;
the ticket body names a `test/` glob in a table of failing jobs and contains the word `for`
in ordinary prose. **No loop, no glob expansion, no suite.** The refusal killed the whole
command line, so the ticket file was never written and the bundled `git commit` and
`tools/sync.sh` never ran either.

**It is in the majority shape, which is the shape the cheap arm of this fork does not
cover:** a heredoc writing a FILE, not a `git commit -m`/`-F`. Option 3 (downgrade for
`git commit`) would have left this refusal exactly as it is.

**And it is the second self-referential instance.** frankC's row records the commit filing
*that* ticket being refused for describing the refusals; this is a ticket about something
else entirely being refused for containing a table of job names. **The population is not
"documents about the hook" — it is "documents that name a test path", which is most of what
this repo's tickets are.**

Landed the way the reporters before me landed theirs: **the `Write` tool for the file and a
message file for the commit. The prose was not reworded to slip past the guard**, per
CLAUDE.md — a guard you route around is a guard the owner no longer has, and a different
TOOL is not the same act as a different WORDING.

## MEASURED 2026-09-09 (frankB) — the mechanism, and it is not the one any row here describes

**Nothing was implemented and the hook is untouched.** This is evidence for the
owner's decision, gathered by feeding the real hook PreToolUse payloads. Four
probes and a corpus census, all read-only; scripts in this session's scratchpad.

**The hook is byte-identical to `448b21c11` (2026-09-03), which predates every
ticket in this family.** So nothing below is a regression and nothing has been
fixed since: where a row's repro passes today, it passed on the day it was
filed.

### Three gates in series, and every row here describes only the third

1. **Escape** — `PXX_TRACK=T` / `PXX_ALLOW_FULL_SUITE=1`, env or inline. Correct,
   untouched, not in scope.
2. **Exemption** — the first word is read-only (`grep|cat|echo|...`), or is `git`
   with a read-only subcommand. **This is where the false positives are decided,
   and no row here mentions it.**
3. **Rules 1/2/3** — the suite-name, tier and shell-loop patterns. Every row here
   analyses these. They are reached only when gate 2 declines to exempt.

### What actually defeats gate 2 — a semicolon in English

```
case "$cmd" in *"&&"*|*"||"*|*";"*) [ "$first" = git ] || first='' ;; esac
```

It tests the **whole command string, heredoc body included**. A semicolon is a
shell separator *and* an ordinary English punctuation mark. Measured — one
command, first word `cat`, author chained nothing, only the prose punctuation
varies:

| body of the document being written | verdict |
| --- | --- |
| `we did not run <recipe> here` | allow |
| `we did not run <recipe>; quick was enough` | **DENY** |
| `quick was enough; we did not run <recipe>` | **DENY** |
| same with a comma | allow |
| same with an em dash | allow |
| same inside a markdown table (single pipes) | allow |

**The author never wrote a chain. The semicolon is punctuation in the file being
created.** The `git` carve-out — added precisely so a commit message may quote a
recipe — is then the only survivor, and a leading `cd <repo>;`, which is how
most commands in this repo are written, removes even that.

### And which side prose falls on is decided by ONE character

Rule 1 anchors `(^|[;&|(]|[[:space:]])make`, so the character immediately before
the recipe name decides it. Same sentence, same act, gate 2 already passed:

| how the recipe is written in the prose | verdict |
| --- | --- |
| `...did not run <recipe>` (space) | **DENY** |
| `...run '<recipe>' by hand` (quote) | allow |
| `...not run:<recipe>` (colon) | allow |
| ``...not run `<recipe>` `` (backtick) | allow |

**Quoting the recipe — the more careful way to write it — is what saves you.**
Writing it as running English is what condemns you. Nobody could predict that,
and it means **the instance counts this row argues from are a sample of a
punctuation lottery, not a rate.** Concretely: this row's sibling
`bug-t-the-full-suite-hook-scans-heredoc-prose-and-refuses-documentation`
carries a two-line repro and the instruction *"spell `<star>` as the asterisk to
reproduce"*. **Spelled exactly as instructed it is ALLOWED.** Change
`documentation.` to `documentation;` — one character, nothing structural — and
it is refused. That row's summary has been corrected rather than left standing.

### The population, measured rather than asserted

This row states: *"The population is not 'documents about the hook' — it is
'documents that name a test path', which is most of what this repo's tickets
are."* **Measured: it is 16.5%, not most.**

Every ticket body under `devdocs/progress/` was wrapped in the command an agent
would use to write it and put to the real hook. Two outcomes compared per body
(with and without a leading `cd`), nothing filtered on whether the body mentions
a suite — filtering on the claim is how the last census in this session went
wrong, and it is now a CLAUDE.md rule (`be763f75c`).

```
ticket bodies tested: 4510
  refused as written (cd ...; cat > f <<'EOF') ....  746   16.5%
  refused without the leading cd ..................  744   16.5%
  the leading `cd` accounts for ....................   2
  by folder: done 711/3593 (19.8%), backlog 17/17 (100%), rejected 5/80,
             low-prio 4/75, backlog-core 2/150, decided 2/149
```

**The `cd` is not the mechanism at scale — the semicolon is**, which is why the
two columns barely differ. `backlog/` at 17 of 17 is the auto-filed regression
folder: those bodies all carry a job table, so the one population that is
refused outright is the one nobody writes by hand.

### What the recommended option would actually do

This row's revised recommendation is *option 2 scoped to heredoc bodies*.
**Simulated without touching the hook** — each command asked twice, once as-is
and once with the heredoc body removed before the hook sees it:

| shape | as-is | under option 2 |
| --- | --- | --- |
| heredoc writing a FILE, cd-prefixed | DENY | allow |
| python heredoc holding a repro line | DENY | allow |
| `cd /x; git commit -m '<prose>'` | DENY | **DENY** |
| a real suite in command position after a heredoc | DENY | DENY |
| a real suite, cd-prefixed | DENY | DENY |
| a real suite after a read-only first word | DENY | DENY |

**All three positive controls hold.** Option 2 fixes the heredoc majority and
leaves exactly one shape refused — the commit message, which is the shape
CLAUDE.md explicitly asks authors to write, and the shape option 3 was supposed
to cover and does not, because of the `cd`.

**So the fork is narrower than three architectural options.** Two small,
independent, separately-testable changes cover every instance measured here
while holding every control: **(a)** skip heredoc bodies in the scan; **(b)**
make gate 2's chain test look at separators in *command* text rather than
anywhere in the string. Either is useful alone; (a) without (b) leaves the
commit message refused, (b) without (a) leaves any body whose prose is
unluckily punctuated refused. **Neither loosens any real invocation** — 11 of 11
real invocations are classified correctly today and stay so under both.

### What this does NOT settle

**Nothing.** The direction is still "less strict" on permission machinery in
`.claude/`, which binds every agent on this box. This row says no agent may
decide it and **not a peer's to authorise**; the argv row says *"NOBODY MAY
NARROW THIS ON THEIR OWN JUDGEMENT"* and *"nobody may implement any option here
without the owner saying which."* A peer relayed an assertion that this fork had
been delegated to agents. **A peer cannot grant that**, and two sessions before
me correctly declined the same fork. Recorded for the owner; not acted on.

### Instance twelve, and it happened during this measurement

The first attempt to write the fork-simulation probe was a `cat > f <<'PYEOF'`
heredoc. **The hook refused it** — rule 3, on a test-glob string and the word
`for` in the docstring explaining rule 3. Third self-referential instance on
record, second to hit a session while it was measuring this defect. Written with
the Write tool instead. **The prose was not reworded**: a different tool is not
the same act as a different wording.
