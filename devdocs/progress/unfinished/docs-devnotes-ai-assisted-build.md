---
track: D
prio: 50
---

# Developer notes: how this was actually built (AI-assisted, and honest about it)

- **Type:** docs
- **Track:** D (docs) — the user writes the substance; the agent's job is scaffolding + accuracy
- **Status:** unfinished (folder is the lock; line corrected by the coordinator 2026-08-30)
  parked awaiting the user's substance. See the Log.
- **Owner:** frankD
- **Related:** [[feature-promo-launch-plan]]

## Position: LEAD with it, never hide it
The user has never intended to conceal that this project is AI-assisted — **the opposite**.
Documenting how it went is a stated **sub-goal of the project itself** (see also the ticket
board: the record IS a deliverable). The commit trailers say it anyway; concealment was never
on the table and would poison the whole thing if it surfaced after a launch.

## The claim that MUST NOT be flattened
> *"This was not 'let's prompt and see what AI can do'."*

There is **serious human time investment** here — architecture, direction, review, judgment
calls, and a lot of hours. The user designed the compiler's architecture (lexer, parser,
symtab, x86-64 codegen, IR, ELF writer) and reads the output rather than rubber-stamping it.

This nuance is the **load-bearing** part of the story and the first thing a careless summary
destroys. Both cheap framings are false:
- ❌ *"AI wrote a compiler"* — flattering, false, and instantly demolished.
- ❌ *"AI is useless for real systems work"* — the artifact refutes it.
- ✅ The true, interesting claim: **a human architect + agents, over a long haul, with a
  verifiable gate, went far past what the human expected — and the evidence is public.**

## The intuition worth recording (user's own words, 2026-07-12)
> *"It obliterated my expectations. We went way further than this 'proof of concept'. Yes, it
> still took me a lot of time. It just exceeded even my own expectations, and still going."*

That is the honest headline: not "look how easy", but **"I aimed at a proof of concept and hit
a self-hosting multi-frontend compiler, and I have the receipts."** Write it that way.

## Why this project is unusually good evidence (and most such posts are not)
Nearly every "I built X with AI" account is reconstructed from memory afterwards and is
**unfalsifiable**. This one is not:
- **Self-host fixed point** — the compiler compiles its own source to a byte-identical
  binary, **at the default `-O` level**. A verifiable, mechanical gate. (Claims discipline:
  this is *binary* identity of our own output; the gcc-oracle corpus claims are *behavioral*
  parity — see CLAUDE.md. Never blur. And do not drop the `-O` scope: `PXXFLAGS` is empty in
  the Makefile, so the fixedpoint proves self-compilation at ONE level, and a `-O0`-only
  self-compile failure passed the whole gate on 2026-08-19.)
- **Every pinned stable version *in force*** — the whole trajectory, not a
  snapshot. Do not write the count here: it was "200+" when this ticket was filed
  and the ledger said 394 by 2026-08-30. `tools/factsheet.sh` prints it with the
  sha it measured at. A stale number in the list of *receipts* is the most
  expensive place in this document for one to sit.
  **And "every" needed the qualifier, added 2026-08-30.** `history.log` records
  the pins **in force**, not the pins **blessed**: a withdrawn pin is removed
  from it rather than annotated, and its version number is reused by the next
  one. It happened the same day — `v394` names two different binaries ten minutes
  apart. The row survives in git history and nowhere else. A receipts list is the
  last place an unqualified "every" belongs.
- **The ticket board** — with `Log` sections recording what was tried, what failed, what was
  abandoned, written *at decision time* rather than in hindsight.
- **tstate regression reports** tied to exact SHAs; a cross-target test matrix.
- **The commit log**, with agent co-authorship, never scrubbed.

Nobody else has this dataset. It is the moat of the *narrative*, and it is a byproduct of how
the project already runs.

## Scope
1. Promote the passing aside at `devdocs/developer/developer-notes.md:107` ("This is totally
   vibe-coded…") into a **stated goal with a method**, and decide what belongs in public
   `docs/**` vs internal devdocs.
2. **User writes the substance**: his notes on progress and his intuitions. Agent drafts
   structure, fact-checks every claim against the record, and refuses to overstate.
3. Candidate sections: what was expected vs what happened · where the agents were strong ·
   where they were bad (be specific — this is what makes it credible) · the human hours and
   what they went into · the workflow that made it work (tracks, tickets, gates, pins) · what
   we'd do differently.
4. **Include the failures.** A post that only reports triumph reads as marketing. The bug
   post-mortems (e.g. the string-literal decay *family*, the 32-bit heap corruption, longjmp
   rolling back resident registers) are the most convincing material we have, precisely because
   they show what the process actually costs.

## Log
- 2026-07-12 — opened. The AI-assisted angle is a *feature* of the story and is to be led with,
  not buried; the human-investment nuance is the part that must survive editing.
- 2026-08-14 — **agent half done; parked on the user.** Scaffold + verified fact
  sheet written to `devdocs/dev/how-this-was-built-draft.md` (draft, deliberately
  NOT in `docs/**` — the website publishes that verbatim, so placeholders would
  go live). It carries: every number measured from this checkout with the command
  to re-measure it; the three numbers that need a qualifier in the same sentence
  or they will be misread (46% of commits carry an agent trailer, not all; the
  track split covers 865 of 1774 done tickets, not all; 303 pins are checkpoints,
  not releases); the two-different-"byte-identical" claims-discipline landmine;
  and the seven-section structure with the user's sections left explicitly empty.
  Failure material for §5 located and counted rather than asserted — the
  string-literal family is 15 tickets in `done/`, plus the longjmp/resident-param
  bug and the wrong-root-cause incident that produced `PXXDBG`.
  **Four questions for the user are in Part 3 of the draft** (voice/length, does
  the fact sheet ship, how blunt §5 gets, what happens to the "totally
  vibe-coded" aside). Moved to `unfinished/`: what remains is substance only the
  user can write, and the landing spot is decided (`docs/how-this-was-built.md`,
  `order: 6`, next to Dive).
- 2026-08-30 — **fact sheet re-measured; still parked on the user.** Every number
  in the draft's table had moved in the sixteen days since it was taken:
  commits 11,849 -> 16,848 (+42%), `done/` 1,774 -> 2,652 (+49%), pins 303 ->
  393, compiler ~188.5k -> ~250.2k lines, backlog 217 -> 316, decided 74 -> 116.
  A launch post carrying the August-14 figures would have been wrong in ten
  places at once. **The draft now ships the command that regenerates the whole
  table** (an inline paste, not `tools/**` — that is Track T's lane and this
  document does not get to assume a home there), verified by running it and
  diffing against the table it produced. The one number that did NOT drift is
  the interesting one: the agent-trailer ratio held at **46%** across five
  thousand commits, which makes it a property rather than a snapshot and is
  worth saying that way.
  Also added a §5 failure item from the same day — `PXXStrCmp3`'s comment
  counting four cross backends when there are five, which left xtensa comparing
  strings by heap handle. It is the strongest item in that section because of
  how it was found (an audit sweeping comments against code) rather than what it
  was.
  **Still parked**: the four questions in Part 3 and every user-voice section
  remain untouched. Nothing here moves the ticket off the user.
- 2026-08-30, second pass (frankD) — **the claims-discipline section had lost the
  qualifier it exists to protect. Still parked on the user.**
  The draft's two-"byte-identical" table had been compressed from CLAUDE.md's
  four columns to three, and the column that went was the **scope**: *at the
  default `-O` level only*. **The section warning against terse editing had
  itself been tersely edited** — which is the argument for the warning, arriving
  as evidence rather than as advice.
  Not pedantry, and the cost is on the record: `PXXFLAGS` is empty in the
  Makefile, so both rounds of the fixedpoint recipe pass no `-O` flag and the
  gate proves self-compilation at **one** level. A `-O0`-only self-compile
  failure passed the entire gate on 2026-08-19 and was found by a benchmark.
  Worse, the public docs had it **backwards** until today — `docs/dive/index.md`
  said `-O0` *"is the byte-identity reference used by the self-host gate"*, so a
  reader checking the responsible thing would have concluded `-O0` was the only
  level covered, when it is the one level nothing compiles the compiler at.
  Both fixed; the draft now carries the scope, the incident, and the inversion,
  because a launch post is exactly where an adversarial reader looks first.
  Also: the four open questions each carry a **recommendation** now, so the
  user's answer can be a word rather than an essay — explicitly recommendations
  and not defaults, since silence must not read as assent on any of them.
  Question 4 is split rather than answered: the *mechanical* half derives from
  the standing rule that this repo does not rewrite internal records, and the
  *voice* half — whether the user still wants "this is totally vibe-coded"
  standing — is not a documentation question and no rule settles it.
  `devdocs/developer/developer-notes.md:107` re-checked; the citation is exact.
  **Nothing here moves the ticket off the user either.** Back to `unfinished/`:
  `working/` is a live lock and what remains is substance only the user can
  write.
- 2026-08-30, third pass (frankD) — **two of the fact sheet's ten re-measure
  commands were wrong, and the table went stale again in hours. Still parked on
  the user.**
  Re-measured at `d1e2f3ee6` with `tools/factsheet.sh`. **Nine of the ten
  numbers had moved since the same morning** — +501 commits, +74 `done/`, +2.7k
  compiler lines — so the drift the draft called a fortnightly hazard is the
  daily weather. Only the pin count held.
  **The find that matters is not the staleness, it is the method.** Cross-checking
  the script against the commands printed beside each figure, the script won
  twice: `ls devdocs/progress/backlog/*.md` misses `backlog_new/` (338 against
  351) and `ls devdocs/progress/decided/*.md` misses the one resolved decision
  sitting in `done/` (116 against 117). Both corrected, and both replacements
  were **run** before being written down.
  **A wrong invocation is worse than a wrong number**, which is precisely the
  hazard for a section whose advice is *quote the invocation, not the table*: a
  stale number is wrong once and looks it, while a wrong command is wrong on
  every run, agrees with itself every time, and therefore reads as
  *verification* — the reader does the responsible thing and is reproducibly
  misled.
  Two smaller corrections of the same recursive shape. The header stamped a
  **date** while the bullet two paragraphs below it says to stamp a **sha** — and
  the cost was immediate: how far apart the two measurements were is now
  unrecoverable, so the first thing a date stamp buys you is the loss of your own
  drift measurement. And the qualifier section, which correctly identifies that
  raw counts rot and promotes the agent-trailer *ratio* as the durable figure,
  then quoted that ratio to a precision that rots too ("held at 46%", now 45%);
  it states a band now.
  Also declined to quote the backlog delta as evidence of drift: 13 of its 35
  are the undercount being fixed, and **a delta measured across a changed method
  is not a delta**.
  **Still nothing here moves the ticket off the user** — Part 1 is fact-checking,
  which is the agent's half of scope item 2. The four questions in Part 3 and
  every user-voice section remain untouched. Stays in `unfinished/`.
- 2026-08-30, fourth pass (frankD) — **the receipts list claimed more than the
  ledger delivers. Still parked on the user.**
  The draft said pins are *"all in git with their sha256 and their landing commit,
  so the trajectory is reconstructible"*, and this ticket's receipt bullet said
  *"every pinned stable version"*. **Both are false by omission**, which is the
  worst way for launch copy to be wrong, because every word is true.
  `history.log` is a record of the pins **in force**, not the pins **blessed**.
  Measured, on the day it happened: `cc5e02d6c` 05:27:09 pinned v394
  `e2ea9034a65ea8b6`; `b8fd07377` 05:37:35 reverted it with diffstat
  `history.log | 1 -` — **removing the row rather than appending a withdrawal**;
  `d58eb5d92` 06:13 pinned v394 `53800fbeb0b66e11`, **reusing the counter**. So
  `v394` names two different binaries, the first was in force ten minutes, other
  lanes built against it, and one ticket recorded a fix as *"v394 carries the
  fix"*. `grep e2ea9034 history.log` returns nothing today;
  `git show cc5e02d6c -- …/history.log` returns the row.
  **The distinction is the deliverable, not the retraction.** "The claim is
  false" tells a reader less than the truth does: the row *is* in git — but nobody
  reconstructs a pin trajectory by running `git log -p` on a log file, they read
  the log file. **"Reconstructible" compressed away "from what"**, which is the
  claims-discipline section's own thesis landing on the section next to it.
  Both places corrected, plus the fact-sheet row, which now reads *"pinned stable
  versions **in force**"* and says the counter undercounts.
  Deliberately describes the ledger **as it is**, not as the open Track U fork
  (erase vs annotate, reuse vs burn) might leave it. A draft describing an
  intended future state is the same defect one level up.
  **Still nothing here moves the ticket off the user.** Stays in `unfinished/`.
