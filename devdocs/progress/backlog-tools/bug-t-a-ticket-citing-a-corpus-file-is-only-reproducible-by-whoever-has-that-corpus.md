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
