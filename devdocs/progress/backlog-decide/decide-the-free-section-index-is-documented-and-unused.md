---
track: U
prio: 45
type: decide
status: backlog
owner: unassigned
blocked-by: []
found: 2026-09-05
found-by: frank-optimize, after re-deriving a playbook answer the hard way three times in one session
summary: "NUMBERS UPDATED 2026-09-06 (fe0c7e2cd): the playbook is 905KB / ~225k tokens / 237 sections, not the 279KB / 70k / 72 quoted below -- it TRIPLED while the pointer stood still, which is this ticket's own thesis happening to it. Fork unchanged. CLAUDE.md tells every session the debugging playbook is large and to LOOK UP THE SECTION, and states that `grep '^## '` lists the 72 sections free. The cost warning is vivid and the free-index clause is subordinate, and the observed result is that the cost-avoidance rule over-applies from 'do not read the file' to 'do not consult the file'. Three measured instances in one night, two of them by the sessions that wrote the surrounding rules. This is a WORDING fork for the owner, not a proposal to restructure the playbook."
---

# The free section index is documented, and it is not being used

**Track U.** Fork of intent in CLAUDE.md's own text; owner's file, so this is
filed rather than edited.

## The observation

CLAUDE.md says, of `devdocs/dev/debugging-playbook.md`:

> **has the tool for your case — LOOK UP THE SECTION.** 279KB, ~70k tokens,
> 72 sections; `grep '^## '` lists them free.

Both halves are correct. The first is vivid and carries a number that hurts. The
second is a subordinate clause after a semicolon. **A rule that stops you paying
70k tokens should not also stop you paying zero**, and in practice it does.

## Measured, one session, 2026-09-05

Three instances, and the two most experienced readers of this file produced two
of them:

1. **frank-optimize** told the coordinator *"no load-independent instrument
   exists on this box"*, then searched for valgrind and qemu TCG plugins. The
   answer was `## \`perf\` being blocked is not "no profiler" — build the
   compiler with FPC and \`-pg\``, **playbook line 4798, and in the section index
   at line 174.** It measured the thing that closed
   [[feature-inline-nonleaf-and-branch-locals]] in eleven seconds with no root.
2. **frank-coordinator** wrote the same claim into the roster without grepping
   the file named for the question.
3. **frank-optimize** reported `objdump -d` as unable to disassemble a pxx ELF.
   The correct mechanism (`-g`, or no section headers are emitted) was **verbatim
   in that session's own notes**, in a session where those notes were loaded.

In every case the search that replaced reading cost more than reading would
have. Nobody declined to consult the index; **nobody considered it**, which is
the tell that the instruction is being read as a prohibition rather than a price.

## The fork

- **(a) Reword.** Lead with the free index and demote the cost:
  *"`grep '^## '` lists its 72 sections free — do that first. Read a section
  only when it is yours; the whole file is ~70k tokens."* Same two facts, order
  reversed.
- **(b) Leave it.** The rule is literally correct and the failures are reader
  error. Costs nothing to keep, and three instances in one night may be a bad
  night rather than a pattern.
- **(c) Something mechanical** — a tool that greps the index for you, so
  consulting it is not a decision anyone has to remember to make.

**Recommendation: (a).** It is a sentence, it changes no behaviour anyone relies
on, and (c) is a larger job that (a) does not block. The argument for (a) over
(b) is that the failing readers were the sessions best placed to know better,
which makes reader-error an expensive theory.

## Explicitly NOT proposed

**Do not read this as an argument to shrink, split or restructure the playbook.**
The file is fine and its size is what makes the index valuable. A restructuring
proposal would rank as a project and never happen, and it would not fix the
thing measured here — the index already exists and already works.

## 2026-09-06 — THE QUOTED NUMBERS ARE STALE, AND THE DRIFT ARGUES THE TICKET'S OWN CASE

Every figure this ticket quotes from CLAUDE.md was corrected at `fe0c7e2cd`:

| quoted here | actual, 2026-09-06 |
| --- | --- |
| 279KB | **905KB** |
| ~70k tokens | **~225k tokens** |
| 72 sections | **237 sections** |

**The playbook TRIPLED while the pointer to it stayed still**, and nothing
errored — the pointer kept answering, with a number that had been true. That is
this repo's own "the name is not the thing", applied to the very sentence this
ticket is about.

**It strengthens the fork rather than changing it.** The ticket's case is that a
vivid cost warning beside a subordinate free-index clause makes sessions stop
consulting the file at all. At 279KB that was an over-application; at 905KB the
cost warning is *more* vivid and the index is *more* valuable, because 237
section headers are the only affordable way in. The correction at `fe0c7e2cd`
also downgraded *"lists them free"* to *"lists the sections for a few thousand
tokens, which is cheap, not free"* — accurate, and it makes the subordinate
clause weaker, which is the direction this ticket argues against.

**Still a wording fork and still the owner's.** What is settled is only that the
numbers no longer support an argument from either side, and that any future
phrasing should carry a date or no number at all: a size in a pointer is a lower
bound with a date on it.
