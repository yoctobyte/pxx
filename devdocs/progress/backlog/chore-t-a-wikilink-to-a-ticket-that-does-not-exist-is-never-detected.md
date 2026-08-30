---
track: T
prio: 30
type: chore
blocked-by: []
summary: "52 distinct ticket-convention [[wikilinks]] across devdocs/progress resolve to no ticket (71 references; 13 cited by live, non-done tickets). Some are renames leaving a dead trail; some appear never to have been filed, which is work hidden behind a link that looks like a citation. Nothing checks."
status: backlog
owner: unassigned
---

# A `[[wikilink]]` to a ticket that does not exist is never detected

- **Type:** chore -- Track T (board tooling, sibling of
  [[chore-t-nothing-re-checks-a-blocked-by-edge-after-its-blocker-closes]]).
- Filed 2026-08-28 by frankB, found while checking whether a p65 ticket's
  reference to `feature-nilpy-corpus-html5lib` pointed at anything. It does not.

## Measured

Restricted to links matching this repo's ticket slug conventions (`bug-`,
`feature-`, `decide-`, `chore-`, `meta-`, `regression-`, `compat-`, `idea-`,
`tstate-`), so memory-namespace links (`project_*`, `feedback_*`), devdocs
filenames and session notes are excluded:

| | |
| --- | --- |
| distinct targets resolving to no ticket | **52** |
| total references | **71** |
| of those, cited by a **live** (non-`done`) ticket | **13** |

The first count I took was **252**, because I matched "not a ticket slug"
rather than "a link that was meant to be a ticket" -- `[[...]]` here spans
several namespaces. The narrowing is recorded because a sweep built on the wide
number would have been mostly noise, and the wide number looked more alarming.

## Two different defects wearing one shape

The second is why this is worth doing.

- **Rename** -- the ticket exists under a different slug. Costs a dead trail:
  someone verifying a claim follows the link, finds nothing, and cannot tell
  whether the reference is stale or the claim is false. Spot-checked:
  `bug-c-bitfield-packing-sizeof-vs-gcc` (a bitfield cluster exists under other
  names), `bug-p-assert-does-not-raise-eassertionfailed` (now
  `compat-pascal-assert-halts-instead-of-raising-eassertionfailed`, which also
  changed type and track).
- **Never filed** -- the link is a promise, not a citation. Spot-checked:
  `feature-nilpy-future-import-noop` and `compat-pascal-subrange-storage-size`
  match nothing under any name. **Both spot-checks were right about the filename
  and wrong about the bucket** — see the 2026-08-30 sweep below: the first was
  *delivered*, and the second was *merged into the ticket that cites it*. Neither
  is "never filed", and neither is distinguishable from it by resolving the name. Same shape as an unexecuted
  `(to file / relay to ...)` row: work recorded as though it has a home, which
  does not.

**Not exhaustively classified.** I spot-checked five of the thirteen live ones.
Which bucket each falls into is the sweep's job, and the distinction matters
because a rename wants a link fixed while a never-filed wants a ticket written.

## Why it is not detected today

`tools/progress.sh check` validates board state -- `working/` locks, stale
boards, dead commit citations -- but nothing resolves `[[...]]` targets. The
existing `DEAD-COMMIT` check is the exact precedent: it exists because a
citation pointing at nothing is worth catching, and it covers only shas.

## Mechanism, with a worked example that is mine

These are written from memory of what a ticket is *about* rather than from its
filename. Mine, filed yesterday: I cited a Track T ticket as
`...-a-skipped-lib-test-job-reports-green-and-manufactures-a-false-last-good`
when the ticket I had just written that day is
`bug-t-a-skipped-job-is-passlike-so-it-becomes-a-false-last-good`. Both describe
the same defect; only one is a filename. Fixed in the same commit as this
ticket.

That is why the count is 52 rather than a handful -- the failure needs no
carelessness, only a descriptive slug and a writer who remembers the subject.

## Fix sketch

A `check` rule beside `DEAD-COMMIT`: resolve every `[[target]]` under
`devdocs/progress/**` against the set of ticket basenames, ignoring the
`project_*` / `feedback_*` memory namespaces and devdocs filenames, and report
the unresolved ones -- loudest for links in live tickets, since a dead trail in
`done/` is history and a dead trail in `backlog/` is a live obstacle.

Worth deciding rather than guessing: whether unresolved links should fail
`check` or only warn. The 52 existing ones argue for warn-first, or the rule
lands red on day one and gets ignored, which is the usual fate of a check that
starts failing.

## Gate

Track T's own: the quick tier green, plus the new rule reporting a
known-dangling link and staying silent on a resolving one -- negative-controlled
in both directions, because a checker that reports nothing looks identical to a
clean board.

---

## 2026-08-30 (frankD) — the check SHIPPED, with half of this ticket's fix sketch

`DANGLING-LINK` landed in `5944ee686`. This ticket stayed open, correctly: the fix
sketch above prescribes **two** exclusions and the implementation has one.

> resolve every `[[target]]` … against the set of ticket basenames, **ignoring the
> `project_*` / `feedback_*` memory namespaces and devdocs filenames**

`tools/progress.py:1781` excludes `self._doc_basenames` — devdocs, the second half.
The memory-namespace half is absent, and the extractor is
`\[\[([a-z0-9][a-z0-9_-]{6,})\]\]`, whose `_` **admits the memory namespace by
construction**.

**Measured over the ranked folders, same run:**

| extractor | names | tickets |
| --- | ---: | ---: |
| `[a-z0-9][a-z0-9_-]{6,}` — as shipped | **40** | 25 |
| `SLUGISH` — already defined at `progress.py:1664` | 12 | 6 |
| ticket-prefix, as this ticket specifies | **11** | 6 |

**The strict instrument is in the same method, 117 lines up.** `SLUGISH =
[a-z0-9]+(?:-[a-z0-9]+){3,}` is hyphen-only, so it excludes `project_*` for free, and
the `PARK-CONDITION-REWRITTEN` scan four lines above the dangling loop uses it. The
dangling loop reaches past it for a looser regex. That is not a missing exclusion so much
as **an available instrument declined at the point of use** — the shape
`devdocs/dev/README.md` §4 calls the section stating a rule being the section breaking it.

Do not simply switch to `SLUGISH`: it needs four hyphen groups, so it drops
`feature-nilpy-dataclasses` (a real, and as it turns out **renamed**, ticket). **The
prefix filter this ticket specifies is the right one**, and the prefix vocabulary should
be *derived from the board* rather than hand-listed — `ls */*.md | sed 's/-.*//' | sort -u`
gives it, and a hand-list written today would have missed `refactor-` (37 tickets), which
owns one of the eleven.

**Scale of the false positive, because it argues against warn-first being enough.**
`project_*` is not a handful of typos: **270 references, 129 distinct names**, 164 of them
in `done/`. Nothing in the tree explains the convention except
`feature-dynamic-compiler-tables:149` — *"see `[[project_dynamic_compiler_arrays_pattern.md]]`
**in agent memory**"* — and a `devdocs/developer/historic/` handover heading *"Related
memory:"*. Zero `project_*` files have ever existed in this repo, in any commit.

**So the check's remedy line is the dangerous part, not the count.** It reads *"Fix the
slug or delete the link; do not leave it to be re-counted"* — an instruction that, followed
on the six tickets it currently flags, deletes references into a second namespace, and
followed board-wide deletes 270 of them. A false positive that merely wastes a reader is
cheap. **This one is phrased as an imperative, and the imperative is destructive.** Fix the
extractor before anyone acts on the advice.

**One clause in the message is also false against its own code.** It says the links are
*"near a blocking phrase"*. They are not: the loop filling `dangling` scans the whole body,
deliberately, and the comment directly above it says so in capitals. The message claims a
bound the code declines to apply, which makes each finding read as more load-bearing than
it is — and a bound is exactly the thing a reader cannot check from the output.

### What the sweep found once the noise was removed

Ran the prefix instrument and judged all eleven by hand. Your two buckets both exist, and
there is a **third you did not name**:

- **rename** — `feature-nilpy-dataclasses` → `feature-nilpy-decorators-dataclass`, in
  `done/`. And `refactor-a-backend-machine-code-lives-in-four-shared-files` → `-six-`,
  where the dead link and the sentence recording the rename were **forty lines apart in
  one file**.
- **never filed** — `feature-nilpy-corpus-html5lib`, `-neuzelaar`, and
  `decide-what-a-reduced-compiler-must-still-self-host`. The last is the expensive one:
  its ticket's own heading is *"Escalated, not guessed"* and the sentence says *"Both open
  questions are filed to Track U"*. One was. **A citation covered for the escalation that
  did not happen** — and Track U's whole rule is escalate-don't-guess, so this is that
  rule failing silently inside the sentence claiming to obey it.
- **never filed AND already delivered** — `feature-nilpy-future-import-noop`. Verified
  against `$(PXX_STABLE)`, not read off the note: `from __future__ import annotations`
  compiles and runs. **This is the bucket invisible in both directions** — no ticket to
  find in `done/`, and the link goes on advertising finished work as pending. It is worth
  a third row in your table, because it is the only one where *both* the record and the
  reader are wrong at once.

- **not a defect** — `measure-before-and-after-on-the-same-pin` is a method maxim someone
  wrote in wikilink brackets. No ticket on this board has ever used a `measure-` prefix.
  A prefix vocabulary derived from the board classifies this correctly and a hand-list
  does not; worth a row in the fix, since "a rule written as a link" will recur.

All four board fixes are landed. The six findings the check still reports are, every one
of them, `project_*`.

### Gate note

Your gate line asks for negative controls in both directions. Add a third: **a
`project_*` link must produce no finding.** It is the case that shipped broken, and a
checker that is silent on a clean board looks identical to one that is silent on the
wrong namespace.

---

## 2026-08-30 (frankD, second pass) — the fixed check reports 0, and four real ones sit where it does not look

`8dc8fa5cb` fixed the namespace and the remedy line. The board then reported **0
DANGLING-LINK**, and that 0 is genuine *for the folders the rule visits*.

**It visits three.** `progress.py:1672` — `if t.status not in ("unfinished", "blocked",
"working"): continue`. The rule was built inside the STALE-PARK family, where a resume
condition is load-bearing, and it inherited that family's aperture. But this ticket's own
defect is not about parks: a dangling link is wrong wherever it sits, which is why the
scan inside that loop deliberately reads the whole body rather than the neighbourhood of
a blocking phrase. **The inner aperture was widened and the outer one was not.**

Running the prefix instrument over all ranked folders: **0 visible, 4 invisible**, every
one in `backlog/`.

| citing ticket | dangling name | verdict |
| --- | --- | --- |
| `feature-p-assertions-directive-and-position` | `bug-p-assert-does-not-raise-eassertionfailed` | **rename** → `compat-pascal-assert-halts-instead-of-raising-eassertionfailed`, in `done/` |
| `compat-pascal-four-type-sizes-…` | `compat-pascal-subrange-storage-size` | **merged into the citing ticket** |
| `feature-c-csmith-differential-fuzzing` | `bug-c-bitfield-packing-sizeof-vs-gcc` | **never filed** |
| `feature-demo-songformatter-pxx-target` | `bug-pascal-subclass-inherited-members` | **unresolvable — left dangling on purpose, see below** |

**Two of those four are the very examples this ticket uses to define its buckets.** The
spot-checks at the top name `bug-p-assert-…` as a rename and
`compat-pascal-subrange-storage-size` as never-filed. Both were still dangling tonight,
and one of the two classifications was wrong. **The check reported a clean board while
its own specification's worked examples were unfixed and one was mis-bucketed** — which is
the same shape as the namespace bug: the instrument agreed with the hypothesis that built it.

### A fifth outcome: MERGED INTO THE CITING TICKET

`compat-pascal-subrange-storage-size` was not renamed and not never-filed. It was
**absorbed** into `compat-pascal-four-type-sizes-disagree-with-fpc-and-every-value-agrees`,
which still carries `*(was compat-pascal-subrange-storage-size, prio 22)*` at the head of
the section that used to be it. The absorbed ticket's citations came with it, so the
merged document was **citing itself as a separate dependency to coordinate with** — *"Do it
together with `compat-pascal-subrange-storage-size`: they are the same job"*, six lines
above the section that IS it.

This is why the spot-check above put it in the wrong bucket, and the reason generalises:
**a merged ticket is indistinguishable from a never-filed one by resolving its name.** The
evidence is inside the citing file, not in the board. It is the only outcome where the
answer is already in the reader's hands and the link is what stops them looking. A merge
that keeps the absorbed ticket's citations manufactures one dangling link per citation,
all pointing at a section of the document doing the citing.

**So the buckets are five, and only two of them are fixed by resolving a name:** rename ·
never filed · never filed but already delivered · merged into the citing ticket · never
was a ticket (a method maxim in brackets).

### One left dangling deliberately

`bug-pascal-subclass-inherited-members` is cited four times by
`feature-demo-songformatter-pxx-target`, called *"on the critical path for two modules"*
and given a *"prio-60 filing"* it does not have. The nearest candidate,
`bug-a-nilpy-subclass-overlays-parent-layout` [A p70], is **done** and covers the layout
arm alone, where the prose names four arms. **Re-pointing would silently mark three arms
resolved**, so the link stays and carries a block quote saying what is and is not known.
`Counter` ships as a mode flag because of it and `feature-nilpy-configparser` is blocked
in practice by it, so this is worth an owning-lane judgement rather than a slug edit.

### Suggested, not done — the aperture

Widening the folder filter for the dangling half is a one-line change in Track T's file
and is not mine to make. Note it needs a **decision**, not just a wider tuple: `done/`
holds most of the board and a dead trail there is history, exactly as this ticket's fix
sketch says. `urgent/`, `backlog/`, `backlog_new/` are the ones where a dangling link is a
live obstacle. Negative control for it: a link that dangles in `backlog/` must produce a
finding — it did not tonight, four times.
