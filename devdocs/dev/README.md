# `devdocs/dev/` — three kinds of file in one directory

52 files, three categories, and **the directory does not encode which is which**.
That matters because they have opposite editing rules, and getting it wrong in
one direction falsifies history.

This page exists because an audit of the live references was dispatched as
*"audit `devdocs/dev/*.md`"*, and taken literally that rewrites ten session
records on the tenth file. The auditor spotted it and left them alone; the
next one might not.

## 1. LIVE REFERENCES — fix them when they are wrong

The default. Everything not named below. These describe how the project works
*now*, are read to decide what to do, and a stale one is a **bug**.

CLAUDE.md is the authority over all of them: *"If a live reference doc
(`devdocs/dev/*.md`) contradicts this section, that doc is the bug: fix the doc,
not the loop."* And CLAUDE.md itself is the owner's — flag a contradiction,
never edit it.

## 2. SESSION RECORDS — never edit, however wrong

A record of what one session actually ran, on the day it ran. **Several contain
figures and gate lines that are false today, and that is correct behaviour for a
record.** Rewriting one falsifies history and is explicitly forbidden by
CLAUDE.md's precedence rule, which also warns that some of them predate the
current per-fix loop and name the heavy pin-gate mode (`gate.sh full`) as if it were
the dev loop. **Never widen your gate on their authority.**

```
handover-2026-06-28-track-abc-cleanup.md   handover-2026-07-18-float-int-perf.md
handover-2026-07-03-optimization-arc.md    handover-2026-08-05-track-d.md
handover-2026-07-04-track-a.md             next-session-indexed-proc-call-prompt.md
handover-2026-07-18-evening-o3-arc.md      next-session-nilpy-bughunt-prompt.md
next-session-pal-prompt.md                 next-session-promo-surface-prompt.md
```

Enumerate them with: `ls devdocs/dev/ | grep -E '^(handover-|next-session-)'`

## 3. CARRIED PROMPTS — a third category, and the reason a filename pattern is not enough

A prompt written for a future session to pick up. Not a historical record, so
correcting one falsifies nothing; not a live reference either, so nothing else
depends on it being right. Fix a stale fact in one freely; do not treat it as
authority.

- `eliah-m4-m5-prompt.md` — Track B / Eliah IDE. Names a `cwd` that may no
  longer exist; read the paths sceptically.

**`*-prompt.md` maps to all three categories, which is exactly why this page
lists files rather than a pattern.** `claude-B-prompt.md` is a **live
reference** — CLAUDE.md:567 cites it in the Platonic-code rule — while four
`next-session-*-prompt.md` files are records and `eliah-m4-m5-prompt.md` is a
carried prompt. A reader inferring the rule from the suffix gets it wrong in
both directions.

`session-roster.md` is also live, and is the one file here that is *supposed* to
be rewritten continuously: it is the coordinator's durable state.

## 4. Obligations parked in prose — where this directory rots

From a full audit of the 42 live references, 2026-08-30 (frankD). Two findings,
and the second is the surprising one.

### The rare failure: an obligation nobody owns

An **obligation** here means a sentence saying the repo owes something — *"to fix
when someone is in there"*, *"should be moved"*, *"not yet written"*. A wide
sweep found 37 obligation-shaped sentences across the live set (excluding
`session-roster.md`, which is a running log). Read individually, **only four are
real**; the rest are prose *about* obligations, correction notes, or conditional
hedges that carry their own escape.

| where | the obligation | why it cannot be discharged |
| --- | --- | --- |
| `autonomy.md` | H1/H2 concurrency hypotheses, *"adopt as a safe default until `claudecap` confirms"* | **`claudecap` is not reachable from this repo** — not in `tools/`, not on `PATH`, one copy under `/data/borg-rescue/`. The named instrument does not exist here, so the deferral is permanent. Annotated in place. |
| `track-b-workarounds.md` | *"Re-check each session against the latest pin … verify the bug ticket is still in `backlog`/`blocked` before assuming the workaround is still needed"* | addressed to **every** session, therefore owned by none. Measured: 7 of its 8 rows wait on bugs already closed. Filed as [[bug-b-seven-of-eight-workarounds-waiting-on-an-open-bug-are-waiting-on-nothing]]. |
| `c-linking-and-crtl-autopull.md` | *"(A future refinement could skip compiling a module whose symbols are never referenced.)"* | a real optimisation idea with no ticket, so the ranker cannot see it and no lane owns it. |
| `vicarius.md` | *"(Filed as a keep-around note; revisit and refine the term later.)"* | no owner and no done-criterion. Low stakes, structurally identical. |

`differential-probes.md`'s *"pick an area nobody has covered and write ten
cases"* is the **healthy** form and is deliberately not in the table: it is
addressed to whoever is reading, needs no state, and cannot go stale.

### The common failure: an obligation already discharged

Far more of this directory rots the *other* way — work that is **finished** and
still described as outstanding. Every one of these was corrected on 2026-08-30
and each had been wrong for weeks:

- `fpc-lcl-compile-probe.md` — all three ranked blockers resolved, one of them
  marked FIXED inside the doc's own text while the closing section still called
  it the *"highest-leverage move"*.
- `name-resolution.md` — **four** claims of open work, all finished. One of them
  assigned Track D a page that had already existed for sixteen days.
- `math-implemented-twice.md` — a three-item *"stale docs to fix"* list with all
  three items discharged, one of them already discharged when the list was last
  edited.
- `eliah-m4-m5-prompt.md` — a section headed `TODO` naming five tickets, all five
  in `done/`.
- `nilpy-object-reclamation.md` — a five-slice plan with no marker that four
  slices landed the night it was written.

**Why this direction and not the other:** a stale obligation is *pessimistic*,
and pessimism is never contradicted by use. An over-tight rule costs its reader
ten wasted minutes and produces nothing wrong, so nobody files a bug about it —
whereas a doc claiming a capability it lacks fails the first time someone tries.
The same asymmetry made `autonomy.md`'s superseded gate ladder survive four
weeks: it demanded a full suite the repo now refuses outright, which is a denial,
not a wrong answer.

### What actually prevents it — not checkability

The tempting rule is *"an obligation must come with a command that answers it."*
That is **not sufficient**, and this directory contains the counter-example:
`name-resolution.md` wrote down its own acceptance test — *"those ten going back
to their real names, with the `#define`s deleted"* — in a form one `grep` settles,
and still went stale for two weeks. **A checkable obligation is cheaper to
recover, but it is not self-executing.** Nothing scheduled the grep.

So, for a new obligation, in order of what actually works:

1. **File a ticket.** The ranker re-reads it; prose does not.
2. Failing that, **name a lane and a trigger** — not "someone", not "when someone
   is in there".
3. A command is worth adding either way, because it makes the *audit* cheap even
   when it does not make the discharge automatic.
4. If it is a standing invitation rather than a debt, phrase it as one — see
   `differential-probes.md` above.

## Adding a file

New session record → prefix `handover-` or `next-session-` **and add it to the
list above**. The list is the mechanism; the prefixes are only a hint, and a
hint that has already been shown to mislead.
