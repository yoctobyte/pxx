---
slug: bug-t-a-stale-blocked-by-in-a-BACKLOG-folder-is-outside-every-aperture
title: "18 ranked tickets are gated on a ticket that has closed, and no check looks there"
track: T
type: bug
prio: 50
status: backlog
owner: ""
created: 2026-09-06
found-by: frankH (one instance, while fixing the exception-escape leak); frankuser (census)
blocked-by: []
summary: "`progress.sh check`'s STALE-PARK aperture covers `unfinished/`, `blocked/` and `working/`. It does NOT cover the per-lane backlogs, which is where open unclaimed work now lives -- so a `blocked-by:` naming a ticket that has since closed reads as GATED to every human and every agent, forever, and nothing reports it. Census 2026-09-06 at da2fea0fd: 18 distinct ranked non-umbrella tickets carry 20 such edges, across backlog-core (6), backlog-pascal (3), backlog-libs (3), backlog-nilpy (2), backlog-windows (2), backlog-tools (1) and unfinished/ (2). LIVE COST, measured not supposed: frankH found the first instance because frankA had told them an hour earlier that the exception-escape leak was blocked on `decide-does-raise-of-an-existing-object-transfer-ownership` -- which was in `done/`, settled for option (a) by the FPC oracle. The fix took an afternoon once the belief was removed. APERTURE NOTE THAT MUST SURVIVE ANY FIX: umbrella tickets legitimately name closed tickets -- membership is an EDGE and a closed member is PROGRESS, not staleness -- and 19 such edges exist. A check that reports those is a check people turn off. RE-CENSUS 2026-09-21 at 2f39aee23 (wider population, stated in the body -- carry both rows, do not read the difference as movement): the real signal is FLAT at 20 non-umbrella edges across 19 tickets, 16 of them fully unblocked and two at p55, while the umbrella noise grew 19 -> 44. That ratio is not an accident and will keep rising: an umbrella accumulates closed members BECAUSE the project progresses, so the false-positive floor of a naive check climbs monotonically with every ticket this fleet closes. The exclusion is load-bearing, not cosmetic."
---

# A stale `blocked-by` in a backlog folder is outside every aperture

## The gap

`check` has a STALE-PARK arm. Its aperture is `unfinished/`, `blocked/` and
`working/` — the folders where parked work lived when it was written. **Open
unclaimed work now lives in the per-lane backlogs**, and those are not scanned.

A `blocked-by:` edge naming a ticket that has since closed therefore:

- reads as **gated** to anyone who opens the ticket,
- reads as **gated** to anyone told about it by a peer,
- is invisible to `check`,
- and never expires.

**It does not error. It answers.** The ticket looks correctly parked.

## The live cost, measured

frankH fixed `bug-a-an-exception-that-escapes-its-handler-or-is-bare-re-raised-still-leaks-its-object`
on 2026-09-06 — 2001 live per 1000 trips down to 3, `d37ee1734`. Its
`blocked-by` named `decide-does-raise-of-an-existing-object-transfer-ownership`,
**which is in `done/`**, settled for option (a) by the FPC oracle: FPC frees a
raised object it did not construct, so `raise` transfers ownership
unconditionally.

**The belief had propagated.** frankA had told frankH an hour earlier that the
row was blocked on that decision. Neither had reason to re-check; the frontmatter
said so and nothing contradicted it.

## The census

At `da2fea0fd`, resolving every `blocked-by` slug to its folder:

| folder | tickets |
| --- | --- |
| backlog-core | 6 |
| backlog-pascal | 3 |
| backlog-libs | 3 |
| backlog-nilpy | 2 |
| backlog-windows | 2 |
| backlog-tools | 1 |
| unfinished/ | 2 |

**18 distinct tickets, 20 edges.** Two of the `backlog-pascal` rows
(`bug-p-thirteen-builtin-type-names...`, `feature-p-the-booleannn-family...`)
went stale *today*, when the type-identity fork was decided — so this accrues
continuously and is not a historical backlog.

## THE APERTURE NOTE, and any fix that ignores it will be turned off

**Umbrella tickets legitimately name closed tickets.** Membership is an EDGE, not
a folder, and a closed member is **progress** — it is how an umbrella records
what has been delivered. There are **19** such edges and every one is correct.

A checker that reports them produces 39 findings of which 19 are noise on the
first run, which is how a check stops being read. **Exclude `type: umbrella` and
`backlog-umbrella/`, and say in the output that the exclusion is deliberate**, or
the next person will "fix" the exclusion.

## Suggested shape

Widen the existing STALE-PARK arm's aperture to every ranked folder rather than
adding a second checker — a second checker is a second copy of the resolution
logic, and the two will disagree. The resolution itself already exists: `check`
resolves slugs to tickets today for DANGLING-LINK.

---

## RE-CENSUS 2026-09-21 — the noise half grew 2.3x while the signal half stayed flat

*Measured by `frankz-e5` (coordinator) at `2f39aee23`, after `frankb-8e`
proposed building this check from scratch, not knowing this ticket existed.
`frankb-8e` cleared one instance the same morning (`c9ba9f950`) and
`frankz-e5` cleared another (`93e6f24eb`).*

**POPULATION, because the two rows below are NOT the same instrument.** This
census walks every `devdocs/progress/*/` directory except `done`, `rejected`,
`known-incompat`, `low-prio`, `rainy-day`, `decided`, `done-followup`; counts a
ticket as open if it parses a frontmatter block; and calls an edge stale if its
slug resolves to a file in one of those excluded directories. That is **693 open
tickets, 64 of them carrying at least one `blocked-by`, 139 edges total.** The
2026-09-06 row said "ranked", which is a narrower set than this one. **Carry both
rows; do not read a difference between them as movement.**

| | non-umbrella stale edges | umbrella/meta stale edges | ratio |
| --- | --- | --- | --- |
| 2026-09-06 `da2fea0fd` ("ranked") | 20 across 18 tickets | 19 | ~1:1 |
| 2026-09-21 `2f39aee23` (above) | 20 across 19 tickets | **44** across 10 | **1:2.2** |

**The thing that changed is the thing the APERTURE NOTE is about.** The real
signal is flat — cleared about as fast as it is created. The false-positive
population **more than doubled in fifteen days**, and it will keep doing so: an
umbrella accumulates closed members *because the project is progressing*, so
**the noise floor of a naive check rises monotonically with every ticket this
fleet closes, forever, by construction.** The exclusion is not a nicety that
makes the output tidier. It is load-bearing, it carries more load every week,
and a check shipped without it would today report 64 findings of which 44 are
the system working.

## The predecessor closed by treating the symptom, and the identical row came back

`chore-t-nothing-re-checks-a-blocked-by-edge-after-its-blocker-closes` is in
`done/` (2026-08-28, owner `pxx-a5`). Its remedy was **"Promoted to `backlog/`"** —
it moved the affected tickets so the ranker could see them, and **did not clear
the edges**. Its own census table lists
`bug-nilpy-songformatter-no-longer-compiles-set-callback-and-get-arity` blocked
by `feature-b-tkhtmlview-in-nilpy`. **That is the exact row `frankb-8e` found
stale on 2026-09-21**, twenty-four days later.

Worse, and this is the part that generalises: **that ticket's own body had said
so the whole time.** Lines 189-201 record the 2026-08-28 finding, name the
closed blocker, and cite the chore ticket — while the frontmatter kept
`blocked-by: [feature-b-tkhtmlview-in-nilpy]` for another three and a half
weeks. This is CLAUDE.md's *"a body that records its own completion is not a
safety net, it is the evidence nobody reaches"* — stated there about `summary:`,
arriving here in `blocked-by:`, which is worse because `blocked-by` is read by a
**program** and the body is not read by anything. **A structured field and the
prose under it went out of sync and only the prose was right.**

## The 16 fully-stale rows at HEAD (every edge they name is closed)

`bug-a-a-hand-built-com-interface-cannot-be-called` p55 ·
`bug-a-address-of-an-open-array-element-points-at-the-marshalling-temp` p55 ·
`bug-n-a-subpackage-directory-does-not-resolve-as-a-module` p55 ·
`bug-n-a-bare-import-of-a-c-header-only-name-builds-a-binary-that-cannot-exec` p50 ·
`refactor-a-the-durable-param-row-is-hand-copied-on-three-registration-paths` p45 ·
`feature-embed-pascal-script` p45 ·
`bug-nilpy-a-handler-binder-unwound-past-by-a-different-exception-still-leaks` p40 ·
`feature-c-diagnostics-name-the-module-they-are-in` p40 ·
`bug-a-basic-string-concat-in-a-unit-free-program-is-a-compiler-error` p35 ·
`feature-nilpy-cycle-collector` p35 ·
`bug-p-an-operator-enumerator-cannot-be-declared-for-an-array-type` p30 ·
`refactor-a-the-frozen-string-store-body-is-written-twice-in-three-backends` p30 ·
`feature-b-rtl-has-no-tdoublerec` p25 ·
`feature-port-windows-pe` p25 ·
`feature-target-wasm` p25 ·
`feature-parallel-load-sampler-refine` p20

Three more carry a mix of live and dead edges: `feature-port-multi-os-abstraction`
(1 of 3), `feature-pcl-cross-platform-gui` (2 of 3),
`feature-pcl-win32-widgetset` (1 of 2).

**These were NOT cleared by this census and no lane has been asked to clear
them** — they sit in six lanes, edges feed `effective_prio`, and four seats were
mid-work under an open pin window when this was measured. Clearing them changes
what `next` hands people, which is a dispatch decision and not a coordinator's.

**WHAT RETIRES THIS TICKET:** the aperture widening in *Suggested shape* above,
landed with a positive control drawn from the umbrella population — a `type:
umbrella` ticket with a closed member, asserted **not** reported. **When you
land it, edit this ticket's `summary:` in the same commit**, because a row that
names its own retirement condition is the one nobody re-reads once the condition
is met (banked `2f39aee23`).

## THE EXCLUSION IS ITSELF A GUARD THAT CAN FAIL SILENTLY, AND IT FAILS GREEN

*`frankb-8e`, 2026-09-21, extending the re-census above past the point it
reached.*

The census argues the umbrella exclusion must be **structural** — derived from
`type: umbrella` — rather than a tuned tolerance, because a tolerance
calibrated against 44 is wrong within weeks. That is right and it introduces a
new failure the check did not previously have.

**Once the check excludes a class, the exclusion can silently widen to
everything, and the check then prints PASS forever.** A broken `type:` read, a
renamed field, a folder that stops being walked, a resolution map built before
a rename — every one of those makes the check **green**, and green is exactly
what a working stale-edge check looks like on a clean tree. There is no
observable difference between *no stale edges exist* and *the walk found
nothing*.

**So the fixture needs BOTH controls and neither is optional:**

| control | asserted | catches |
| --- | --- | --- |
| an umbrella ticket with a closed member | **IGNORED** | the exclusion inverting or being dropped |
| a non-umbrella ticket with a closed blocker | **FOUND** | the walk, the resolver, or the aperture silently emptying |

Without the second, `PASS` is unfalsifiable. Without the first, the check
becomes the thing it was built to avoid — 44 findings that are the system
working, on its first outside run.

This is the re-census's own cry-wolf argument pointed one level in: **the
exclusion exists to stop the check being ignored, and it thereby becomes the
part most likely to fail undetected.**

## WHY THE 2026-08-28 REMEDY MADE IT QUIETER RATHER THAN BETTER

*`frankb-8e`'s framing, sharper than the paragraph above it and kept in its own
words.*

**The predecessor's remedy and its defect were in different categories.**
*"Promoted to `backlog/`"* is a fix for **visibility**. The defect was the
**correctness of a machine-read field**. Moving the tickets made the stale rows
reachable by the ranker **without making them true** — so the ranker then read
a wrong `blocked-by` *more reliably than before*.

The symptom was treated so effectively that the cause got quieter. That is the
shape to look for when a remedy and a defect do not name the same thing: not
"the fix did not work", but "the fix worked, on a different property, and
removed the pressure that would have found the real one."
