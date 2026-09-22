---
slug: bug-e-every-world-reports-meta-name-rijn-so-a-banner-cannot-name-the-scene
track: E
prio: 60
type: bug
status: backlog
owner: ""
created: 2026-09-22
found-by: lekkerzeilen-7a (cost, the retraction, and the fix), relayed by frankuser and franks-5b, enumerated by frankz-e5
tags: [lekkerzeilen, perf, measurement, name-is-not-the-thing, positive-control]
blocked-by: []
summary: "ROOT CAUSE: `meta.name` is COPIED FROM A PARENT BUILD AND NEVER UPDATED, so a derived world inherits its ancestor's name -- and the world DIRECTORY, the only true identity, is never emitted anywhere. So a banner cannot name the scene and no measurement can be attributed from its own log. ENUMERATED, not sampled: twelve `world/*/index.lzi`, and `meta.name` is one of three values across all of them. TILE COUNT IS **NOT** THE DISCRIMINATOR AND THIS TICKET SAID IT WAS FOR ONE HOUR -- `roofs` and `uv` agree on name=rijn, tiles=4, pounds=1, routes=5, i.e. EVERY field a banner prints, and that 4-tile class is the one the shipping scene is in; `revet-control`, `revet-test` and `skel-test` are a THREE-WAY identical collision at name=wageningen, tiles=2, pounds=1, routes=5. Tile count separates the 4-tile class from the 432-tile class and does nothing WITHIN either. 7a's verdict on how both of us got there: **a guard that passes the FAR case is not evidence** -- it was tested against 432-tile `rijn`, never against the near twin, a positive control drawn from the easy end. AND THE SURVIVING DISCRIMINATOR IS ONE ROW WIDE: `rijn` and `rijn-v9` separate only on `pounds`, 163 versus 162, so any scheme that identifies a world by its shape is one edit away from collapsing. FIX, two halves, root cause above both: (1) emit the world DIRECTORY, which is unique by construction and cannot drift from a copied field; (2) DONE 2026-09-22 by 7a, and better than asked -- the stamp is now `region=<invocation> tiles=<n> worldindex=<sha16 of the index.lzi that actually resolved> twins=<computed set>`; tile count ALONE would not have caught the case that bit, since `uv` is a 4-tile twin and only the index hash separates them. A guard that must name the ambiguity should COMPUTE the set it cannot exclude rather than list it (`OK (class of roofs: 4 tiles; indistinguishable from: uv)`), because `world/` gains directories. THE PROFILE IS NOT AFFECTED: `PROFILE-2026-09-21.md:29` records `--region rijn` as an INVOCATION and independently quotes `atan2` calls/frame at 46.0 on roofs against 1,258.4 on rijn (`:222`), a 27x gap no 4-tile run could produce -- a relay of this put the roofs side at 6.8, which appears nowhere in the file; read off the source 2026-09-22. AND THOSE COUNTS ARE CPYTHON'S, stated at `:222`, so they transfer on the argument that the program logic is identical, which is an argument and not a pxx measurement. THREE DOCUMENTS ARE MISLABELLED -- `FINDINGS-demo-leak.md:10` and `:691`, `PREREG-water-sim-bisect.md:9` -- and their NUMBERS STAND (interleaved legs within one scene; a kB/s rate does not depend on which 4-tile world it was). What breaks is REPRODUCTION: `--region rijn` gives 432 tiles and matches nothing. The fix is a label, not a re-run."
---

# Every world reports one of three `meta.name` values

## The root cause, which is neither of the fix halves

**`meta.name` is copied from a parent build and never updated.** A derived world
inherits its ancestor's name. **The directory is the only true identity and it is
never emitted anywhere**, so every downstream guard reconstructs identity from
shape — which is what several seats have now done badly, including this ticket.

## Enumerated, 2026-09-22, `/home/neo/lekkerzeilen`

    dir              meta.name     tiles  pounds  routes
    roofs            rijn              4       1       5   <-+ identical on every
    uv               rijn              4       1       5   <-+ field a banner prints
    roof-test        rijn              2       1       5
    rijn             rijn            432     163     619
    rijn-v9          rijn            432     162     619       <- differs by ONE pound
    rijn-v7          rijn            432     214     619
    rijn-v6          rijn            419     210     622
    rijn-flat        rijn-flat       154      54      89
    wageningen       wageningen       40       2       7
    revet-control    wageningen        2       1       5   <-+ three-way identical
    revet-test       wageningen        2       1       5   <-+
    skel-test        wageningen        2       1       5   <-+

Twelve worlds, **three distinct names**. This is the whole population on disk,
not a sample.

## Why "discriminate on tile count" is wrong, and this ticket said it

**The first version of this ticket recorded tile count as the discriminator**,
on `roofs`=4 against `rijn`=432. It is not one. **`roofs` and `uv` agree on all
four fields**, and the 4-tile class is the class the shipping scene is in — so
the proposed guard is blind exactly where it is needed. `revet-control`,
`revet-test` and `skel-test` are a **three-way** collision of the same shape.

**7a reached the same over-claim independently and retracted it against
itself.** Its verdict is the transferable sentence and it belongs here rather
than in a playbook: **a guard that passes the FAR case is not evidence.** Both
of us validated against 432-tile `rijn` — a positive control drawn from the easy
end of the population, which passes and certifies nothing about the near twin.

**AND THE SURVIVOR IS ONE ROW WIDE.** `rijn` and `rijn-v9` are separated only by
`pounds`, **163 against 162**. A shape-based identity is therefore one world
edit away from collapsing, so even a correct shape scheme is a stopgap, not the
fix. That is the argument for emitting the directory rather than a better
fingerprint.

## Fix half (2) is DONE — 7a, 2026-09-22 — and it answers better than the ask

The stamp line is now three fields, not the one this ticket asked for:

    region=roofs  tiles=4  worldindex=<sha16>  twins=uv

**7a was not already stamping tile count. It stamped `region=roofs` — the
INVOCATION, what was asked for rather than what loaded — and those two being
different is the entire bug.**

- `tiles` narrows to a shape.
- **`worldindex` is sha256 of the `index.lzi` the region actually RESOLVED to**,
  taken on the **input** side, because no output can name the file.
- **`twins` is the set the row still cannot exclude, COMPUTED at run time.**

**And this is the point the ticket's original ask got wrong.** `tiles` alone
would have made historical rows adjudicable — that part of the instinct was
right — but **it would not have caught the case that actually bit.** `uv` has 4
tiles too and agrees on name, pounds and routes; **only the index hash separates
them.** A written-down twin list would go stale the first time someone adds a
world, which is this same failure one level up. Hence computed, not listed.

**Near-case rule again, applied to a FIX rather than to a probe:** a
discriminator validated against the far case (432-tile `rijn`) passes, and the
nearest neighbour defeats it.

## The remaining fix

1. **Emit the world DIRECTORY.** Unique by construction; cannot drift from a
   copied field.
2. **Record the shape in every perf stamp.** This is the half that pays: fixing
   the banner alone makes future logs trustworthy and leaves every existing one
   permanently unadjudicable.

**Pattern for any guard that must state the ambiguity: COMPUTE the set it cannot
exclude, never list it** — 7a's repaired form is `OK (class of roofs: 4 tiles;
indistinguishable from: uv)`. `world/` gains directories, and a written-down
list of twins is the same failure a second time.

## Blast radius, and do not over-withdraw

**The profile is NOT affected.** `PROFILE-2026-09-21.md:29` records
`--region rijn` as an **invocation**, not a banner reading, and it separately
quotes `atan2` calls per frame at **46.0 on `roofs`** against **1,258.4 on
`rijn`** (`:222`) — a 27x gap no 4-tile run can produce. That label stands.

**Two values were in circulation for the roofs side and only one is real: 46.0.**
`grep -n '6\.8'` over the file returns **no match** (`asin` is 3.5 and 0.2).
Settled 2026-09-22 by reading the source at both ends; **do not carry 6.8 as a
second row.**

**Its provenance is worth more than the correction.** 6.8 originated in 7a's
message and was passed on by a relaying seat **that had already read the correct
figure the same day** — the commit body of `2efde35a3` says in plain text
*"rijn 1258.4/frame, roofs 46.0"*, and that seat had quoted that commit to the
owner four messages earlier. **So a wrong number was relayed by someone holding
the right one**, having quoted a peer's recollection over their own read. It
survived because **the conclusion never depended on the digit** — 46 or 6.8, the
gap against 1,258.4 is a gap no 4-tile run produces — which is exactly the shape
that lets a wrong figure travel a long way.
**And the counts are CPython's**, stated at `:222` — they transfer on the
argument that the program logic is identical, which is an argument and not a
measurement under pxx. `franks-5b` raised that limit against its own row before
anyone asked. `umbrella-lekkerzeilen-runs-at-15-fps` has
been corrected accordingly.

**Three documents are genuinely mislabelled:** `FINDINGS-demo-leak.md:10` and
`:691`, `PREREG-water-sim-bisect.md:9` — all say `rijn` while describing a
4-tile world. **Their NUMBERS STAND.** Those are interleaved legs within one
scene, and a leak rate in kB/s does not depend on which 4-tile world it was.
**What breaks is REPRODUCTION** — anyone running `--region rijn` gets 432 tiles
and matches nothing. **The fix is a label, not a re-run.**

## Why those documents are recoverable at all, and it is the argument for fix (2)

Their author wrote the **SHAPE beside the name, every time** — *"a settled rijn
world (4 tiles, everything resident, nothing streaming)"*. **An 80%-accurate
name carried next to a 100%-accurate measurement, and the measurement is what
identifies the run.** Every document that did this is adjudicable today; every
one that recorded only the name is not.

## The destructive step that took the oracle out, and the lesson is not "scope your globs"

**7a's harness run step opened with `rm -f "$R"/run-*.txt`** to clear what it
was about to rewrite. The glob was wider than the set the step owned:
`run-C1.txt`, the CPython baseline measured an hour earlier, matched it.
Launching the pxx pair **deleted the oracle artefact** after its number had been
published onward. The reduction survives as recollection (55 windows, median
22.396 fps); the file, its stamp, its banner and its session sha do not.

**The lesson 7a drew, which is the transferable one:** not *scope your globs*,
but **a step may clear what it is about to rewrite and nothing else.** 7a held a
note to itself, written three days earlier, about taking a baseline before
something overwrites it, and did not apply it to a destructive line in its own
tool.

**AND 5b'S SHARPENING IS THE PART THAT GENERALISES PAST THIS REPO:** this is the
documented glob-`rm` hazard arriving **inside a committed script** — the case
CLAUDE.md's hook deliberately exempts, on the grounds that a script is *"reviewed
once, run as a unit"*. **The script was correct when reviewed. The directory grew
underneath it.** In 5b's words: **a glob is a query, and you cannot review a
query against files that do not exist yet.** The exemption is sound for the
interactive hazard it was written for and does not cover this; recorded here
rather than acted on, because loosening or tightening a guard is the owner's.

## What would retire this

A run whose own output identifies its scene **without reference to any argument
the operator remembers passing**, plus at least one historical row re-attributed
from a recorded discriminator rather than from recollection.
