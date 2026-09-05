---
slug: bug-t-a-ticket-citing-a-corpus-file-is-only-reproducible-by-whoever-has-that-corpus
track: T
type: bug
prio: 45
status: backlog
found: 2026-09-05
found-by: frankS, measured and filed by frank-coordinator
owner: ""
blocked-by: []
summary: "`library_candidates/` is GITIGNORED and fetched per-checkout, and every checkout holds a DIFFERENT subset -- measured 2026-09-05 across ten: three have none at all, and of the seven that have some, no two match. Only frankA and frankZ hold `fpc-testsuite`. Meanwhile 19 tickets in OPEN folders cite a path under `library_candidates/`, and NONE of them says the input has to be fetched. The damage is not that a reader cannot reproduce -- it is that THE READER CANNOT TELL WHY. A missing corpus and an already-fixed bug produce the same silence, and a triager reaches for the second, because a ticket that will not reproduce looks stale rather than unrunnable. This composes with the two apertures already recorded (filed from the visible half, probed from the slug) into a third: PROBED ON A MACHINE WITHOUT THE INPUT. The remedy that works is frankS's: a hand-built reconstruction in the ticket body, which carries its own inputs and cannot be misread."
---

# A ticket citing a corpus file is only reproducible by whoever has that corpus

## The measurement

`library_candidates/` is in `.gitignore:36` and tracked nowhere
(`git ls-tree -r origin/master | grep -c '^library_candidates/'` → **0**). Each
session fetches what it needs. Taken 2026-09-05 across ten checkouts:

| checkout | holds |
| --- | --- |
| frankA | `fpc-rtl` `fpc-testsuite` `rtl-generics` |
| frankB | `busybox` `html5lib` `reportlab` `rtl-generics` `tinycss2` `webencodings` |
| frankC | `busybox` `c-testsuite` `lua` `sqlite` |
| frankD | `busybox` `c-testsuite` `lua` |
| frankS | `busybox` `sqlite` |
| frankZ | `c-testsuite` `fpc-testsuite` `lua` `sqlite` |
| frankwasm | `rtl-generics` |
| frankH, frank-optimize, frank-coordinator | **absent entirely** |

**No two match. Three have nothing. `fpc-testsuite` exists in two of ten.**

Open-folder tickets citing a `library_candidates/` path, counted by folder rather
than by a glob across all of them:

```
working 1 · unfinished 3 · blocked 1 · backlog-core 1 · backlog-nilpy 2
backlog-tools 2 · backlog-pascal 3 · backlog-libs 2 · backlog-cfront 3
backlog-umbrella 1                                          = 19
```

**None of them says the input must be fetched first.**

## Why this is worse than "cannot reproduce"

> **The failure is not that the reader cannot reproduce it. It is that the reader
> cannot tell WHY they cannot reproduce it.** — frankS

**A missing corpus and an already-fixed bug produce the same silence**, and a
triager reaches for the second, because **a ticket that will not reproduce looks
stale rather than unrunnable.** The wrong reading closes a live ticket, which
this tree already knows is far worse than a false positive that wastes a probe.

**This is a third aperture and it COMPOSES with the two already recorded.** A
ticket filed from a refusal has sampled the visible half; a repro built from the
slug narrows again; and now a probe run on a machine without the input narrows a
third time — **all before anyone measures anything, and all three produce the
same artefact.**

Worked instance: `tgeneric4.pp`, `ugeneric4.pp`, `tgenfunc17`/`18` are cited as
evidence in three Track P tickets. **They do not exist in the checkout of the
session holding those rows.** The evidence came from a session that had the
suite, and nothing in any of the three says so.

## The remedy that actually works, and it is not a frontmatter field

frankS did the right thing without being asked: rather than fetch (**an outbound
act**) or note the absence, it **reconstructed the shape by hand** and put the
two-file reconstruction **in the ticket body**. Its reconstruction reproduces
FPC's exact error, `Global Generic template references static symtable`.

> **A repro that carries its own inputs cannot be misread as stale.** It is a
> strictly stronger artefact than a corpus citation: it works on every box, it
> carries its own provenance, and it does not decay when a corpus moves.

**So the preferred fix is a convention plus a check, in that order:**

1. **A ticket whose repro needs an unfetched input must carry a self-contained
   reconstruction, or say in the SUMMARY that it does not have one.** The summary,
   because it is the only part everyone reads and a triager deciding "stale?"
   never gets further.
2. **A `check` rule**: any open ticket citing a path under `library_candidates/`
   (or any gitignored tree) without either a reconstruction or an explicit
   "requires corpus X" line is a finding. Mechanical, and it fires whether or not
   the author thought they needed it — which is the only kind that catches this
   class.

**Positive control for whoever builds the check:** the three generics tickets
above, in their pre-fix state. A rule that does not flag them is not the rule.

## Not in scope

**Do not fetch corpora to close this.** Fetching is an outbound act, per-session,
and making 19 tickets reproducible by populating ten checkouts is the expensive
answer to the cheap problem — and it decays the moment an eleventh session
starts.

## AUDIT 2026-09-05 — the hazard did NOT fire on tonight's campaign. Intersection EMPTY.

Asked for by frankuser and run by frank-coordinator, **which was not in the
campaign and closed nothing** — the sweeping session must not audit its own
output.

**Population:** 61 tickets added to `done/` or `rejected/` on origin in 14 hours.
(Renames land as adds, so moves out of `working/` are captured.)

**Instrument 1 — does any closure cite a corpus?** Scanned for
`library_candidates`, `fpc-testsuite`, `c-testsuite`, `rtl-generics`,
`tgeneric*.pp`, `ugeneric*.pp`, `tgenfunc*`, `busybox`, `sqlite`, `lua`,
`quickjs`, `duktape`, `reportlab`, `html5lib`, `tinycss2`, `webencodings`.
**Seven hits.** Every one closed on a **FIX**, none on a non-reproduction:

| ticket | closing sha | tree | corpus cited | present there? |
| --- | --- | --- | --- | --- |
| multi-dim array typedef corrupts neighbours | `5435c14a7` | frankC | busybox | **yes** |
| undeclared identifier in a file-scope initializer | `3bfc63fef` | frankC | busybox, sqlite | **yes** |
| undeclared identifier used as a value | `54ad11adf` | (frankC, per its own text) | busybox, c-testsuite, lua, quickjs, sqlite, duktape | **yes** for all present ones |
| pointer to a typedef'd array segfaults | `249e29cfa` | frankC | busybox | **yes** |
| two same-named file-scope statics alias | `ec1a1d7b6` | (frankC, per its own text) | sqlite | **yes** |
| `of object` derails the Delphi generic anchor | `1ea430c95` | frankB | rtl-generics | **yes** |
| two same-named statics share one procs row | `3f427655e` | frankC | c-testsuite, sqlite | **yes** |

frankC's checkout holds `busybox c-testsuite lua sqlite`; frankB's holds
`rtl-generics`. **Every cited corpus was present in the checkout that closed the
ticket.**

**Instrument 2, which fails differently — does any closure REST on a
non-reproduction?** Rather than trusting the citation scan, matched the closure
*basis* across all 61: *"does not reproduce"*, *"cannot reproduce"*, *"no longer
reproduces"*, *"not reproducible at HEAD"*, *"already fixed by"*.

> **Count: ZERO. Not one of tonight's 61 closures rests on a non-reproduction.**

So the hazard had nothing to fire on. A second pass looking for summaries that do
**not** assert a fix found 18 — three real tickets and fifteen auto-filed
`regression-*` rows with empty summaries — and **none of the 18 cites a corpus.**

### The one that is the INVERSE of the hazard, and it is the reassuring row

`bug-p-a-method-pointer-type-derails-the-delphi-generic-alias-anchor`
(`1ea430c95`, frankB) is the case this ticket fears, run backwards. Corpus rung 6a
(**rtl-generics `Generics.Defaults`, five `of object`**) had been recorded green
**twice, by two independent sessions, six days earlier, with byte-identical
figures** (`code=671512B procs=1661`). Re-measured at tip it **failed outright** —
a regression from `b613b5fcf`, bisected with pin-seeded builds.

**The corpus being PRESENT is what turned a stale green into a found regression.**
Which is the argument for the reconstruction remedy rather than against it: the
value is in the input existing where the probe runs, not in where it came from.

### The aperture of this audit, stated because a negative result inherits it

- **Instrument 2 matches a fixed phrase list.** A closure written as *"probed and
  it works now"* would not match. That is the real residual and it is why
  instrument 1 was run independently rather than as a filter.
- **Two of the seven shas did not resolve by checkout reflog** — the known failure
  mode of that instrument. Corroborated by each ticket's own text naming frankC,
  which fails differently.
- **This checkout holds NO corpus at all**, so what was verified is *presence in
  the closing checkout*, not that the probe actually read the file.
- **Scope: 14 hours, `done/` and `rejected/` only.** Says nothing about closures
  before that window.

**The campaign's numbers stand as reported:** `ready --track P` 53 → 39, and no
closure in it is reopened by this ticket.

## MEASURED 2026-09-06 — the denominator, and a live case where it changed an answer

The argument above was made without a count. Here is one.

`library_candidates/` is in `.gitignore` (line 36), so **it never arrives by
pull.** Counted across the checkouts on this box:

| | checkouts |
| --- | --- |
| **have** `library_candidates/` | **10** — frank1, frankA, frankB, frankC, frankD, frankS, frankwasm, frankZ, pxx, trackt-watch |
| **lack** it | **9** — frank2, frankH, frank-optimize, frank-rust, frank-user, frank-subcoord, frank-coordinator, frank-coord-core, frank-coord-front |

**Live working sessions are on both sides of that line**, and nothing about a
checkout announces which side it is on.

**So the same sweep, run by two agents, returns two different answers and neither
errors.** The one run without the corpus silently measures a smaller population
and reports a clean result — the null-result shape, from a tool that is working.

**The live case (frankA, 2026-09-06).** A directive sweep over
`/usr/share/fpcsrc/3.2.2` closed with a stated residual: *"a name used only by
Delphi, a vendor unit or FPC 3.3+ is still invisible."* The real gap was that
`fpcsrc/3.2.2` holds `compiler`, `packages` and `rtl` and **no `tests`** — and
FPC's testsuite was already on the box at
`library_candidates/fpc-testsuite`. Re-running there found **9 more names** and
**2 more false positives**.

**Both halves of this ticket fire in that one story:** the corpus was present for
the agent that eventually looked, absent from nine other checkouts, and named in
a residual rather than enumerated. **The instrument to state beside any
corpus-derived count is which corpus root was on disk** — `ls` it, and say so.
