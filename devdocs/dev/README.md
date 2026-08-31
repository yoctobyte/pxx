# `devdocs/dev/` — three kinds of file in one directory

58 files, three categories, and **the directory does not encode which is which**.
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

## 2. SESSION RECORDS AND ARCHIVES — never edit, however wrong

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

Enumerate **those** with: `ls devdocs/dev/ | grep -E '^(handover-|next-session-)'` —
and note that the pattern does not cover the block below, which is the whole
reason both blocks are written out here rather than derived.

**2b. ARCHIVES — same rule, different reason.**

Not a record of a session. These are **verbatim copies of a live doc as it stood
before it was cut down**, kept so nothing was lost when the handbooks were
compressed on 2026-08-31. They are excluded from the audit for the same reason
records are — correcting one destroys the thing it exists to preserve — but the
justification is different: a record is history, an archive is a *deleted
previous version*. The live successor is the file to fix.

```
handbook-rationale.md
session-roster-history.md
```

`handbook-rationale.md` (74KB) holds the evidence, incidents and worked
reasoning that CLAUDE.md carried until 2026-08-31; its live successor is
CLAUDE.md itself, now rules only. `session-roster-history.md` (1.5MB) holds the
coordinator's 322 dated log sections — do not read it, `grep '^## '` it; its
live successor is `session-roster.md`.

**Those two successor names are deliberately in prose and not in the block
above.** The block is machine-read: every filename inside it is excluded from
the audit, so naming a live file there would silently drop it — which is the
exact defect `tools/docaudit.py` documents at the top of its own source, and
which a positive control caught here on the first attempt.

**Neither is reachable by a filename pattern**, which is the point section 3
makes about `*-prompt.md` arriving one category early: the exclusion list is a
list because no rule generates it.

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

`session-roster.md` is also live, and is the coordinator's durable state. It
used to be an append-only log and grew to 1.5MB — ~384k tokens, read at the
start of every coordinator session. On 2026-08-31 the log moved to
`session-roster-history.md` and the live file was cut to the current role plus
the operational facts that outlived their day. **Keep it that way: it is
rewritten, not appended to.**

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

### The failure that was NOT here — limitation sentences

Swept 2026-08-30 on the premise that **a false limit is quieter than a false fix
and survives longer.** A wrong instruction gets re-tested by the next person who
follows it. A wrong *caveat* — "this cannot be checked", "no oracle exists for
this", "this only applies to X" — gets believed, reads as conscientious, and
**stops anyone re-checking**. So limitation sentences deserve more scepticism
than instruction sentences, not less.

Every candidate in the live references passed. `differential-probes.md`'s
*"`crtl_decl_probe` is the odd one out: it has no oracle"*, and
`debugging-playbook.md`'s *"from outside there is no way to tell whether the
ranges drifted"* and *"there is no way to tell which you are holding from the
report alone"* — all three are true, and all three are correctly scoped.

**They are safe for a reason worth copying, because it is a property of the
sentence rather than of the author.** Each pairs its limit with the instrument
that gets past it, in the same breath:

| the limit | the escape, named immediately |
| --- | --- |
| no oracle for `crtl_decl_probe` | it is a **census**, and `readelf -d` is the check |
| can't tell drift from lookup *from outside* | `PXXDBG=a.srcmap:*` — "settled it in one run" |
| can't tell which profile you hold *from the report* | record the `-O` level the way you record the sha |

**A bare limit is the dangerous shape; a limit with a named escape route defuses
itself**, because the reader who wants past it is handed the way past it instead
of being told to stop. So the sweepable question is not "is this limitation
true?" — which is expensive — but **"does this limitation say what to do
instead?"**, which is visible at a glance. A caveat that ends in a full stop is
the one to check.

## Adding a file

New session record → prefix `handover-` or `next-session-` **and add it to the
list above**. The list is the mechanism; the prefixes are only a hint, and a
hint that has already been shown to mislead.
