# How this was built — draft scaffold + verified fact sheet

**Status: DRAFT, not published.** This file lives in `devdocs/` on purpose. The
website publishes `docs/**` verbatim from git, so a half-written essay in
`docs/` would go live with its placeholders showing. It moves to
`docs/how-this-was-built.md` (top level, alongside `dive/`) once the substance
is written — see *Where it lands* at the end.

For [[docs-devnotes-ai-assisted-build]]. The ticket splits the work explicitly:
**the user writes the substance; the agent drafts structure and fact-checks
every claim.** This file is the agent half. Sections marked **[USER]** are
deliberately empty — they are the user's voice and the agent must not invent
them. Sections marked **[VERIFIED]** carry numbers measured from this checkout,
each with the command that produced it, so they can be re-run before publishing
rather than trusted.

---

## Part 1 — The fact sheet [VERIFIED]

Measured at **`d1e2f3ee6`**. **Re-run before publishing** — and this is no longer
a caution, it is a measurement taken twice. The table was first taken on
2026-08-14, and **every single number had moved sixteen days later**: commits by
42%, `done/` tickets by 49%, compiler lines by 33%. A launch post carrying the
August-14 figures would have been wrong in ten places at once.

Then it was re-taken the same morning it was written up, and **nine of the ten
had moved again within hours** — +501 commits, +74 `done/`, +5 `rejected/`,
+2.7k compiler lines. Only the pin count held. So the drift is not a fortnightly
thing to check before publishing; it is the daily weather, and the table is a
photograph.

(The backlog row moved further still, 316 to 351, but that one is **not**
evidence of drift and is not quoted as such: 13 of those 35 are the undercount
fixed below, not tickets that were filed. A delta measured across a changed
method is not a delta.)

**And note what could not be said about that.** The earlier table was stamped
with a *date*, so how far apart the two measurements actually were is now
unrecoverable — same morning, but four hours or ten? **The first thing a date
stamp costs you is the ability to measure your own drift.** That is the rule the
second bullet below already stated, and the line above it was breaking. It now
carries a sha.

**Re-measure with `tools/factsheet.sh` and do not hand-edit a single number** —
hand-editing one is how the other nine stay stale. It prints the table, the sha
it measured at, and the qualifiers that have to travel with three of the figures.

Track T owns it, and it exists because the first version of this paragraph
referenced a path that did not exist. Three notes from its two runs, all worth
knowing before you quote anything it prints:

- **It disagreed with the hand count above on three of ten numbers, and the hand
  count was right each time.** Resolved decisions live in `decided/`, not `done/`;
  pins are a ledger file (`stable_linux_amd64/default/history.log`), not a
  commit-message pattern; and `compiler/builtin/**` is compiler source, so a
  top-level-only glob undercounts by 14% on one missing subdirectory. Each wrong
  definition is now a comment in the script. **The hand count could only serve as
  the oracle because it had been published first** — which is the argument for
  the fact sheet living in the essay at all.
- Its header stamps the **HEAD commit's** date, not the day you ran it. Usually
  the same; say "measured at `<sha>`" rather than "as of `<date>`" and the
  distinction stops mattering.
- **On the second run the disagreement reversed: the script was right and two of
  the ten re-measure commands printed in the table below were wrong**, both
  undercounting. `ls devdocs/progress/backlog/*.md` missed `backlog_new/` and was
  13 light (338 against 351); `ls devdocs/progress/decided/*.md` missed the one
  resolved decision that landed in `done/` and was 1 light (116 against 117).
  Both are fixed in the table.

  **A wrong invocation is worse than a wrong number**, and this section is where
  that matters most, because its whole advice is *quote the invocation, not the
  table*. A stale number is wrong once and looks it. A wrong command is wrong
  every time anyone runs it, agrees with itself on every run, and therefore reads
  as **verification** — the reader does the responsible thing, gets a reproducible
  answer, and is reproducibly misled. Publish no command you have not run against
  a second method.

| claim | value | how to re-measure |
| --- | --- | --- |
| Commits | 17,349 | `git rev-list --count HEAD` |
| Elapsed | 2026-05-24 → 2026-08-30, ~14 weeks | `git log --reverse --format=%ad --date=short \| head -1` |
| Commits with an agent co-author trailer | 7,793 | `git log --format=%b \| grep -ci "Co-Authored-By: Claude"` |
| Pinned stable versions **in force** | 394 | `cat stable_linux_amd64/default/VERSION`; the log is `stable_linux_amd64/default/history.log`. **Not the number blessed** — a withdrawn pin is removed and its number reused, so this counter undercounts; see the qualifier below |
| Tickets resolved | 2,726 | `ls devdocs/progress/done/*.md \| wc -l` |
| Tickets **rejected** | 56 | `ls devdocs/progress/rejected/*.md \| wc -l` |
| Decisions recorded | 117 | `ls devdocs/progress/decided/*.md devdocs/progress/done/decide-*.md \| wc -l` — **not** `decided/` alone |
| Open backlog | 351 | `ls devdocs/progress/{backlog,backlog_new}/*.md \| wc -l` — **not** `backlog/` alone |
| Compiler source | ~253.0k lines | `find compiler -name "*.inc" -o -name "*.pas" \| xargs wc -l` |
| Library source | ~75.6k lines | `find lib -name "*.pas" -o -name "*.c" -o -name "*.h" \| xargs wc -l` |

### Numbers that need a qualifier, not a footnote

Three of the above will be misread if stated bare. Say the qualifier in the same
sentence:

- **7,793 of 17,349 commits carry an agent trailer** — that is 45%, not 100%.
  Do not round it to "written by AI"; the split *is* the story the ticket says
  must survive editing. The ratio has sat **between 45% and 46% across sixteen
  days and five thousand commits**, which makes it a real property rather than a
  snapshot — say so, it is more convincing than the raw count.

  **State it as a band.** It read "held at 46%" until this line was re-measured
  and found to be 45%, which is the same error the table above makes, one level
  up: this section correctly identifies that raw counts rot and promotes the
  ratio as the durable figure, then quotes the durable figure to a precision that
  rots too. What is stable is the *band*; a post that says "held at 46%" gets
  falsified by the next fortnight exactly like the counts did.
- **Track counts in `done/` cover 1,760 tickets, not 2,726.** Only tickets filed
  after the `track:` frontmatter convention landed carry the field, so
  `grep -h "^track:" devdocs/progress/done/*.md | sort | uniq -c` under-reports
  the early months. Current split of the ones that have it: N 682, A 416, P 242,
  T 140, B 140, C 86, D 21, R 5, W 3, O 2, S 1, U 1, plus 21 combined-track
  spellings (`A+S` 16, `A+T` 2, `A+N`, `A+O`, `B+S`). Quote it as "of the tickets
  that record a track", or not at all — the uncovered 966 are not a rounding
  error, they are 35% of the finished work and they are the *early* months, so
  any per-track story told from this table is a story about the second half of
  the project.
- **A pin is not a release.** A pin blesses a self-host-verified binary that
  other tracks then build against; it is an internal checkpoint. The interesting
  property is the trajectory, not the count — every pin in force is recorded in
  `stable_linux_amd64/default/history.log` with its sha256, its source commit and
  a timestamp, and the file is in git.

  **State the reconstructibility claim with its "from what", because the ledger
  and git answer different questions.** This bullet read *"all 393 are in git
  with their sha256 and their landing commit, so the trajectory is
  reconstructible"* until 2026-08-30, and that is false by omission — which is
  the worst way for launch copy to be wrong, because every word of it is true.

  What is actually true, and it is still a strong claim:

  > **The ledger is a record of the pins in force, not of the pins blessed.** A
  > pin that is withdrawn is *removed* from `history.log` rather than annotated,
  > and the version counter is *reused* by the next pin. The withdrawn row
  > survives in git history and nowhere else.

  Measured the day it was written, because it had just happened:

  | | |
  | --- | --- |
  | `cc5e02d6c` 05:27:09 | pin **v394** `e2ea9034a65ea8b6` |
  | `b8fd07377` 05:37:35 | revert — diffstat `history.log \| 1 -`, `pin.log \| 1 -` |
  | `d58eb5d92` 06:13 | pin **v394** `53800fbeb0b66e11` — the counter reused |

  So `v394` names two different binaries in this repo's history. The first was in
  force for **ten minutes**, other lanes built and measured against it, and
  tickets cite it by name — one recorded a fix as *"v394 carries the fix"*. Today
  `grep e2ea9034 history.log` returns nothing; `git show cc5e02d6c --
  stable_linux_amd64/default/history.log` returns the row.

  **Why this belongs in the essay rather than in an erratum.** Nobody
  reconstructs a pin trajectory by running `git log -p` on a log file — they read
  the log file. A reader who checks `history.log` finds one v394 row and has no
  way to learn a different one existed. **"Reconstructible" compressed away "from
  what"**, which is this section's own thesis landing on this section: the
  qualifying words carry the entire distinction and terse styles drop them first.

  If the ledger's behaviour changes — the open Track U fork is *erase vs
  annotate* and *reuse vs burn the counter* — **this paragraph changes with it,
  and not before.** A draft that describes an intended future state is the same
  defect one level up.

### The claims-discipline landmine

The project has two different "byte-identical" claims and the essay is exactly
where they get blurred (`CLAUDE.md`, *Claims discipline*):

| claim | what is identical | to what | scope |
| --- | --- | --- | --- |
| self-host fixedpoint | the **binary** | our own previous output | **at the default `-O` level only** |
| zlib / C corpora vs the gcc oracle | the program's **output** | the output of a gcc-**built** zlib | behavioural, not machine code |

We do not emit gcc's machine code and must never imply it. In a post that will
be read adversarially, write these uncompressed — the qualifying words
("output", "built with", "our own", "at the default `-O` level") carry the whole
distinction and terse editing drops them first.

**The fourth column was missing from this table until 2026-08-30, and its absence
is the thing this section warns about.** CLAUDE.md's original has it; the copy
here had been compressed to three columns, and the column that went was the
qualifier. The section advising against terse editing had itself been tersely
edited.

That scope is not pedantry, and the cost of dropping it is on the record.
`make compiler/pascal26` builds `compiler.pas` at the **default** level —
`PXXFLAGS` is empty in the Makefile, so both rounds of the fixedpoint recipe pass
no `-O` flag at all. Nothing in the loop compiles the compiler at any other
level. A `-O0`-only self-compile failure therefore **passed the entire gate** on
2026-08-19 and was found by a benchmark.

And the public docs had it backwards, which is how adversarial reading finds
things: `docs/dive/index.md` stated that `-O0` *"is the byte-identity reference
used by the self-host gate"* — the inverse — until 2026-08-30. A reader doing the
responsible thing and checking whether the gate covers `-O0` would have come away
believing it was the **only** level covered, when it is the one level nothing
compiles the compiler at. **Say "it reproduces itself at one optimisation level,
and here is which", not "it reproduces itself."**

---

## Part 2 — The structure

The ticket's position, restated so a later editor cannot lose it: **lead with
the AI-assisted angle, never bury it.** The commit trailers say it anyway, and
documenting how it went is a stated sub-goal of the project. Both cheap framings
are false — "AI wrote a compiler" is flattering and instantly demolished; "AI is
useless for real systems work" is refuted by the artifact. The true claim is the
interesting one: *a human architect plus agents, over a long haul, against a
mechanical gate, went well past what the human expected — and the evidence is
public.*

### 1. What I aimed at, and what I got

**[USER]** — the headline, in the user's own words. The intuition already
recorded on the ticket (2026-07-12) is the seed, not the final copy:

> "It obliterated my expectations. We went way further than this 'proof of
> concept'. Yes, it still took me a lot of time. It just exceeded even my own
> expectations, and still going."

Frame: not "look how easy" but "I aimed at a proof of concept and hit a
self-hosting multi-frontend compiler, and I have the receipts."

### 2. Why this account is falsifiable and most are not

Agent-draftable from Part 1; the argument is already settled on the ticket.
Nearly every "I built X with AI" post is reconstructed from memory afterwards
and cannot be checked. This one can:

- the **self-host fixed point** — a mechanical gate, not a testimonial;
- **393 pinned binaries** with shas — the trajectory, not a snapshot;
- the **ticket board**, with `Log` sections written at decision time rather than
  in hindsight — including the 37 rejected ones;
- **tstate regression reports** tied to exact shas, across a cross-target matrix;
- the **commit log**, agent co-authorship intact, never scrubbed.

That dataset is a byproduct of how the project already runs, which is why it
exists at all.

### 3. The human hours, and what they went into

**[USER]** — the load-bearing section, and the first thing a careless summary
destroys. Architecture (lexer, parser, symtab, x86-64 codegen, IR, ELF writer),
direction, review, judgment calls. The user reads the output rather than
rubber-stamping it. Agent's job here is to *not write it* and to flag any
sentence elsewhere in the piece that implies otherwise.

### 4. Where the agents were strong

**[USER]** for the assessment. Agent may supply candidate evidence: the breadth
work (a frontend at a time), the mechanical sweeps, the volume of ticket-shaped
fixes, the willingness to write the post-mortem down at the time.

### 5. Where the agents were bad — be specific

This is the section that makes the piece credible, and it is the one with the
most material already on disk. Candidates, all real and all documented:

- **The string-literal decay *family*.** Not one bug — **21** tickets in `done/`
  matching `string-literal`, across the C frontend (`bug-c-string-literal-binop-decay`,
  `bug-c-sizeof-string-literal`, `bug-c-string-literal-to-pointer-prefix`),
  NilPy (`bug-nilpy-char-vs-string-literal-ordering-compares-an-address`,
  `bug-nilpy-print-string-literal-reserves-8mb-of-bss`) and even a backend
  (`bug-riscv32-string-literal-to-class-field`). The lesson the repo drew from
  it is `devdocs/dev/normalise-dont-special-case.md`: fixing one arm of a double
  case and not grepping for the sibling is how a family forms.
- **A comment that counted wrong, and cost a whole target its string ordering.**
  `PXXStrCmp3`'s header says *"the four cross backends had NO ordered-string arm
  at all"*. There are **five**. The fix went to i386/aarch64/arm32/riscv32 and
  xtensa was never visited, so `'zzz' < 'aaa'` on xtensa compared the two heap
  **handles** as signed integers and answered by allocation order — demonstrated
  2026-08-30 under `qemu-xtensa`, both comparisons wrong on both ABIs
  ([[bug-a-xtensa-has-no-ordered-string-compare-and-sorts-by-heap-handle]]).
  This is the best single item in this section and it is worth telling in full,
  because of *how it was found*: not by a test, not by a user, but by an audit
  that swept the tree for comments asserting invariants and checked each against
  the code. **A count in a comment reads as a complete enumeration, so nobody
  counts.** The audit that found it
  ([[audit-a-a-comment-asserting-an-invariant-is-a-claim-about-a-sibling-arm-nobody-checked]])
  produced a rule worth quoting in the essay: *a comment goes stale exactly when
  the sentence and its truth-maker can be changed independently.* The fact sheet
  above is itself an instance — ten numbers that all rotted in sixteen days —
  which is why it now ships with the command that regenerates it.

- **`bug-a-o2-resident-param-stale-after-longjmp`** — an optimizer holding a
  parameter in a register that `longjmp` rolls back. The expensive shape: no
  crash, a plausible wrong value far from the cause.
- **A wrong root cause recorded in a ticket** because reasoning was cheaper than
  measuring. That incident is *why* `PXXDBG` exists and why
  `devdocs/dev/debugging-playbook.md` opens with "measure, do not reason". It is
  the single most honest thing in the record and should not be left out.

**[USER]** decides which of these carry the section and what the verdict is; the
agent should not editorialise about its own failure modes.

### 6. The workflow that made it work

Agent-draftable, checked against `CLAUDE.md` and
`devdocs/dev/parallel-tracks.md`: tracks as collision lanes rather than a
taxonomy, the ticket board as the queue, the per-fix gate
(`make compiler/pascal26` — which *is* the fixedpoint — plus `gate.sh quick`),
pins as the blessed ground other lanes build on, Track T sweeping the matrix
asynchronously, and Track U as the escalation lane for "escalate, don't guess".

The non-obvious part worth stating: the gate is what makes agent throughput safe
at all. A compiler that cannot reproduce itself cannot leave a tree.

### 7. What we would do differently

**[USER]**.

---

## Part 3 — Open questions for the user

Each carries a recommendation, so an answer can be a word rather than an essay.
They are recommendations, not defaults — none of these is settled by taking
silence for assent.

1. **Voice and length.** Long-form essay, or a shorter public page linking to
   the record? The material supports either.
   *Recommendation: the long form.* The falsifiability argument (§2) is what
   makes this account different from every other "I built X with AI" post, and it
   does not survive compression — it needs the receipts beside it.
2. **Does the fact sheet ship?** Part 1 as a table is unusually strong evidence
   and unusually easy to check. Publish it, or keep the numbers inline in prose?
   *Recommendation: ship it, with the re-measure command beside it.* A table a
   reader can re-run is the whole claim; the same numbers in prose read as
   assertions and cannot be checked. The risk is staleness, and it is now
   handled — `tools/factsheet.sh` regenerates the table and stamps the sha.
3. **Section 5's verdict.** Which failures carry it, and how blunt?
   *Recommendation: blunt, and led by how a bug was FOUND rather than what it
   was.* The strongest item in §5 is the `PXXStrCmp3` comment counting four cross
   backends when there are five — not because the bug was large, but because it
   was found by an audit sweeping comments against code, which tells the reader
   something about the process. A post that only reports triumph reads as
   marketing; one that reports its own detection methods reads as engineering.
4. **`devdocs/developer/developer-notes.md`'s "This is totally vibe-coded"
   aside** (line 107, checked 2026-08-30) — the ticket asks to promote it into a
   stated goal with a method. Rewrite that line in place once the public page
   exists, or leave the internal note as the historical record it is?
   *Recommendation: leave the line, add a pointer.* Half of this derives from a
   standing rule and half does not, and the split is worth naming. The
   **mechanical** half derives: an internal note is a record of what someone
   thought at the time, and this repo does not rewrite those — the public page is
   the "stated goal with a method", so promoting does not require demoting. The
   **voice** half does not derive and is yours alone: how you characterise your
   own project is not a documentation question, and no rule settles whether you
   still want that sentence standing.

## Where it lands

`docs/how-this-was-built.md`, top level next to `dive/`, linked from
`docs/index.md`. Reasons: it is launch-narrative material
([[feature-promo-launch-plan]]), it is about the project rather than the
language, and `docs/language/**` and `docs/reference/**` are both wrong homes
for it. Needs a `title:` and an `order:` in frontmatter like every other page —
suggest `order: 6`, immediately after Dive.

Nothing moves to `docs/` until the **[USER]** sections are written; a published
page with placeholders is worse than no page.
