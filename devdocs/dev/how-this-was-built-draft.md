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

All measured at `HEAD` on 2026-08-14. **Re-run before publishing** — every one
of these grows weekly, and a stale number in a launch post is exactly the kind
of thing that gets checked.

| claim | value | how to re-measure |
| --- | --- | --- |
| Commits | 11,849 | `git rev-list --count HEAD` |
| Elapsed | 2026-05-24 → 2026-08-14, ~12 weeks | `git log --reverse --format=%ad --date=short \| head -1` |
| Commits with an agent co-author trailer | 5,477 | `git log --format=%b \| grep -ci "Co-Authored-By: Claude"` |
| Pinned stable versions | 303 (`v1`…`v303`) | `cat stable_linux_amd64/default/VERSION`; the log is `stable_linux_amd64/default/history.log` |
| Tickets resolved | 1,774 | `ls devdocs/progress/done/*.md \| wc -l` |
| Tickets **rejected** | 37 | `ls devdocs/progress/rejected/*.md \| wc -l` |
| Decisions recorded | 74 | `ls devdocs/progress/decided/*.md \| wc -l` |
| Open backlog | 217 | `ls devdocs/progress/backlog/*.md \| wc -l` |
| Compiler source | ~188.5k lines | `find compiler -name "*.inc" -o -name "*.pas" \| xargs wc -l` |
| Library source | ~67k lines | `find lib -name "*.pas" -o -name "*.c" -o -name "*.h" \| xargs wc -l` |

### Numbers that need a qualifier, not a footnote

Three of the above will be misread if stated bare. Say the qualifier in the same
sentence:

- **5,477 of 11,849 commits carry an agent trailer** — that is 46%, not 100%.
  Do not round it to "written by AI"; the split *is* the story the ticket says
  must survive editing.
- **Track counts in `done/` cover 865 tickets, not 1,774.** Only tickets filed
  after the `track:` frontmatter convention landed carry the field, so
  `grep -h "^track:" devdocs/progress/done/*.md | sort | uniq -c` under-reports
  the early months. Current split of the ones that have it: N 482, A 182, T 68,
  B 61, C 39, P 30, D 2, O 1. Quote it as "of the tickets that record a track",
  or not at all.
- **303 pins is not 303 releases.** A pin blesses a self-host-verified binary
  that other tracks then build against; it is an internal checkpoint. The
  interesting property is that all 303 are in git with their sha256 and their
  landing commit, so the trajectory is reconstructible — that is the claim
  worth making, not the count.

### The claims-discipline landmine

The project has two different "byte-identical" claims and the essay is exactly
where they get blurred (`CLAUDE.md`, *Claims discipline*):

| claim | what is identical | to what |
| --- | --- | --- |
| self-host fixedpoint | the **binary** | our own previous output |
| zlib / C corpora vs the gcc oracle | the program's **output** | the output of a gcc-**built** zlib |

We do not emit gcc's machine code and must never imply it. In a post that will
be read adversarially, write these uncompressed — the qualifying words
("output", "built with", "our own") carry the whole distinction and terse
editing drops them first.

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
- **303 pinned binaries** with shas — the trajectory, not a snapshot;
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

- **The string-literal decay *family*.** Not one bug — 15 tickets in `done/`
  matching `string-literal`, across the C frontend (`bug-c-string-literal-binop-decay`,
  `bug-c-sizeof-string-literal`, `bug-c-string-literal-to-pointer-prefix`),
  NilPy (`bug-nilpy-char-vs-string-literal-ordering-compares-an-address`,
  `bug-nilpy-print-string-literal-reserves-8mb-of-bss`) and even a backend
  (`bug-riscv32-string-literal-to-class-field`). The lesson the repo drew from
  it is `devdocs/dev/normalise-dont-special-case.md`: fixing one arm of a double
  case and not grepping for the sibling is how a family forms.
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

1. **Voice and length.** Long-form essay, or a shorter public page linking to
   the record? The material supports either.
2. **Does the fact sheet ship?** Part 1 as a table is unusually strong evidence
   and unusually easy to check. Publish it, or keep the numbers inline in prose?
3. **Section 5's verdict.** Which failures carry it, and how blunt?
4. **`devdocs/developer/developer-notes.md`'s "This is totally vibe-coded"
   aside** — the ticket asks to promote it into a stated goal with a method.
   Rewrite that line in place once the public page exists, or leave the
   internal note as the historical record it is?

## Where it lands

`docs/how-this-was-built.md`, top level next to `dive/`, linked from
`docs/index.md`. Reasons: it is launch-narrative material
([[feature-promo-launch-plan]]), it is about the project rather than the
language, and `docs/language/**` and `docs/reference/**` are both wrong homes
for it. Needs a `title:` and an `order:` in frontmatter like every other page —
suggest `order: 6`, immediately after Dive.

Nothing moves to `docs/` until the **[USER]** sections are written; a published
page with placeholders is worse than no page.
