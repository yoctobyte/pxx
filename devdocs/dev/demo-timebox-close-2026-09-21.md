# Python demo timebox — close-out, 2026-09-21

**The owner timeboxed the Python demos to today.** From tomorrow the window is
the **release** and **stabilising ESP32**. This page exists because four lanes
produced results today across **two repositories**, several tickets, a hardening
map and a pile of relays that live only in message history — and it stops being
writable the moment anyone's context rolls.

**Written by `frankz-e5` (coordinator), which measured NONE of this.** Every
number below is another seat's, cited to who took it and against what
population. Where a claim is second-hand and I could not reach the source, it
says so. Where I found a live contradiction, I record it as a contradiction
rather than picking a side.

> **The one-line answer: all three Python demos build and run under pxx. None of
> the three can be obtained in runnable form by a stranger.** The compiler is
> not the blocker any more; **packaging is**, and packaging was never in scope
> today.

---

## 1. The three Python demos

**Authoritative source: `lekkerzeilen@devdocs/DEMO-READINESS-2026-09-21.md`,
by `lekkerzeilen-7a`.** Do not re-derive these rows here; that file carries the
full matrix, the method, and a perishability protocol. Read it first.

**⚠ ONE ROW IN IT IS SUPERSEDED BY ITS OWN AUTHOR'S LATER WORK.** Line 136 reads
*"nobody in the fleet has measured it"* about the cost of reaching a runnable
state from scratch — and `lekkerzeilen@8868d45`, three commits later, measures
exactly that. The document was not touched again (`git log` on that path stops
at `253b51d`). Raised with 7a; flagged here because this page points at that
file as the authority and will not do so silently.

### What ran, and against what

| demo | tree | observable | verdict |
| --- | --- | --- | --- |
| **uforth** | `07ffdb1` | Forth-2012 suite, 252 lines | **byte-identical to CPython**, `Total 0` errors |
| **songformatter** | `12cf40e` | `keydemo` key analysis, 21 lines | **byte-identical to CPython** |
| **lekkerzeilen** | `25e188f` | 825 KB PNG, boat making 6.9 kn | **3 of 3 frames**, interleaved |

**These are end-to-end passes on real programs against third-party corpora, not
smoke tests** — 7a's characterisation and it is the right one. uforth's is the
strongest single result the project has: a third-party conformance corpus,
exact match.

### The pin is why lekkerzeilen renders

**On pin v413 (`f94c2a7e2396d2be`) the demo rendered 0 of 3**, throwing blocker
03's `TypeError: object is not callable`. **On pin v414 (`aeadb1754b80b622`) the
same clean checkout renders 3 of 3.** Both rows are kept, each labelled with the
pin sha it measured; **neither replaces the other**, because they are true about
different compilers.

**The pinned failure was late and quiet** — it built, started, loaded the world
and rendered its 512×512 chart *before* throwing. **A build-success matrix would
have shown six green cells.** That is why the observable is a PNG.

**Not re-taken:** the uforth and songformatter PIN rows still read `f94c2a7e`,
because that is the compiler they were measured on. They passed on v413 and were
not re-run on v414. They are labelled, not silently inherited.

### Populations, so these numbers are re-derivable

- `warn` counts `: warning:` lines, the expression `runbin.sh` itself uses.
- Every cell was generated from `logs/*/row.txt` by `gen-matrix.py`. **Nothing in
  that table was typed by hand** — and the arm label is derived from each row's
  own recorded sha, after 7a fixed a hardcoded constant that would have printed
  new measurements under an old label.
- **Interleaved** HEAD/PIN each round, so drifting box load cannot manufacture
  the split; rate-measured both ways, because a 0/3 and a 3/4 are different
  phenomena.

---

## 2. What "works" does NOT mean — packaging, per demo

**This is the section that matters tomorrow.** All three green rows above
borrowed something that a stranger does not get.

### lekkerzeilen — needs ~168 MB that is not in the repo

`git archive HEAD` produces **zero** `world/` files. `world/` is gitignored
deliberately (*"Built world tiles — regenerable, never committed here"*) and is
**15 G on disk**. A fresh clone builds and cannot run. **This has nothing to do
with pxx and is equally true of the CPython demo.**

**But the requirement is far smaller than 15 G**, measured by 7a in
`lekkerzeilen@8868d45` by tracing successful `open()` calls and then
**constructing and verifying** the result:

| component | size |
| --- | --- |
| fresh clone (293 files) | 14 MB |
| `world/DEFAULT` | 4 KB |
| the single world DEFAULT names (`roofs`) | 154 MB |
| **total** | **~168 MB** |

Two optional rows were **measured rather than assumed**: `assets/facades.lzx` is
probed for, gets `ENOENT`, and the demo renders anyway; `world/gauges.lzg` was
moved aside and it rendered identically — **though a four-second shot does not
exercise tide, so "not required to draw a frame" is not "unused."**

**The decision is the owner's** and 7a states it narrowly: does the shipped demo
point at a small world like `roofs`, or at the 14 G `rijn` corridor.

### ⚠ songformatter — two records say opposite things and BOTH ARE TRUE

**This is the single most misleading pair in the project right now** and a future
reader will hit it. Put them side by side:

| source | says | population |
| --- | --- | --- |
| `DEMO-READINESS`, today | builds 4.3 s, runs 0.3 s, **IDENTICAL** | `keydemo.py` → `key_analysis.py` |
| `bug-nilpy-render-backend-...`, 2026-08-30 | **does not compile**; spins forever | `render_backend.py`, `SongFormatter.py` |

**Neither is wrong.** `SongFormatter.py` is a Tkinter GUI needing `markdown`,
`tkhtmlview`, `PIL` and `fitz`; no pxx shims exist for any of them. What compiles
and runs is `key_analysis.py`, exercised by a `keydemo.py` **written for the
matrix and not tracked in any repository.**

**So "songformatter works" and "songformatter does not compile" are two correct
answers about two different programs that share a name.** The key-analysis
*library* survives pxx; songformatter *as a product* does not have a pxx story.
**Always say which one.**

**And the failing measurement is 22 days old, on a compiler three pins back.**
`bug-nilpy-render-backend-py-compile-does-not-terminate` (p55, `unfinished`) was
filed against **pin v392 (`60b060bb54a8`)** on 2026-08-29 and parked 2026-08-30:
`timeout 1500` hit, 25:00 wall, 95% CPU, RSS flat — a tight non-allocating spin,
**not slowness**. The other two entry modules reached `render_backend.py:114` on
`w, h = img.getSize()`.

> **NOBODY HAS RE-MEASURED SONGFORMATTER AT HEAD OR AGAINST v414.** That is the
> cheapest open question on this page. v414 closed blocker 03 (*a field shadows
> another class's method*) and 04 (*a `@property` setter runs when the receiver
> has no slot*) — both exactly the shape that produced songformatter's 08-09
> wall (`"set_": no such member`). **Whether those walls moved is unknown and
> one compile would say.**

`songformatter_settings.ini` sits tracked in the pxx repo root, committed
2026-07-28. **No statement of why exists.** I am recording that rather than
inferring it proves anything.

### uforth — the strongest row, and it is wired into the tiers

**Correcting my own first draft, which said no packaging gap was recorded:** the
gap is recorded and it is deliberate, and uforth is far better wired than the
other two.

- **In the build and in the tiers.** `test-uforth` runs a smoke plus **17
  corpora** — 4 `.for` files and 13 Forth-2012/ANS word sets — each run
  **differentially against CPython running the same `uforth.py`**. There are no
  `.expected` files *on purpose*: *"uforth's OWN corpora, run DIFFERENTIALLY …
  so there is nothing recorded here to go stale when uforth moves."*
- **Green today**, independently of 7a's matrix: tstate report
  `20260921T073045Z-1ce2c86-borg`, host borg, tier **full**, all 13
  `test-uforth#…` shard jobs `pass`.
- **The source is an external clone** — `UFORTH_SRC ?= $(HOME)/projects/uforth`,
  SSH URL, **fetched by no script**. That is a decided policy, not an oversight:
  `decide-3rd-party-vendor-vs-fetch` (2026-08-01) — *"corpus stays
  fetch-gitignored."* A stranger needs a **writable** checkout, because the word-set
  drivers are generated into the uforth tree at run time.

**⚠ AND THE GREEN HAS A SILENT-SKIP HAZARD, which is a guard that cannot fail.**
If `$(UFORTH_SRC)/uforth.py` is absent the recipe prints
`test-uforth: SKIP — no uforth tree at …` **and exits 0**. Nothing downstream
distinguishes that from a real pass — **the tstate report for today says
`skips: 0`**. On a box without the checkout, this row is green and means
*nothing was measured*. That is the exact class this project banked all day, sitting
live in the demo suite.

**A second discrepancy, unresolved:** the Makefile's bench header says the
**pinned** compiler *"is too old to lex uforth's char-code literals"*, while 7a's
matrix records uforth building and running IDENTICAL on pin `f94c2a7e`. Both are
in the tree. Either the comment is stale or the two targets differ. **Not
resolved here.**

---

## 3. pxx is slower than CPython on both comparable workloads

**uforth's suite: 236 s under pxx against 155 s under CPython — 1.52×.** Same
direction as, and far milder than, the lekkerzeilen frame-rate pair
(`lekkerzeilen@devdocs/perf/FRAME-RATE-2026-09-20.md`).

**`franks-5b` spent today decomposing where that time goes**, on a three-arm
build whose arms are proven distinct (`d8b0c6fc5cac`, `70b4768485e9`,
`aeadb1754b80` — the last being pin v414's own binary, reproduced by accident).
Its stated non-claim is recorded here because it is the honest half: comparing
that decomposition to its 9.0% one-module synthetic answers the scaling question
**only if the two are otherwise comparable, and they are not.**

---

## 4. TSP — characterised, deliberately not started

**Sources:** `devdocs/dev/tsp-compile-wall-inventory-2026-09-20.md` (with a
2026-09-21 re-sweep) and `devdocs/dev/tsp-rows-4-8-what-shares-a-cause.md`, both
`frankH`.

**47 of 67 compile.** Population is `tsp/**/*.py` = **67**. **Do not quote 67
without checking it** — `find . -name '*.py'` over the whole TSP archive answers
**91**. The author's own statement of why that matters: *the denominator moved
because the archive is 91 files and only 67 are under `tsp/`, so any figure
quoted without the glob is unrecoverable rather than merely imprecise.* Measured at pxx `45b8571d7` (09-20) and re-measured at `8e60c44be` plus
the case-fold fix (09-21): **identical**, 47 of 67 both times.

| row | what | state |
| --- | --- | --- |
| 1 | `import threading` | **not a defect** — configuration, the `--threadsafe` flag |
| 2 | `import wave` | **CLEARED** (`60d4d96b0`, `mimic_wave.pas`) |
| 3 / 3b | the `ctypes` seam | **PARKED BY THE OWNER** — see below |
| 4 | `dataclasses.replace` | characterised, **not started**, p45 |
| 5 | `@dataclass(frozen=True)` | characterised, **not started**, p40 — *the refusal is correct* |
| 6 | `subprocess.run(cwd=)` | reproduced, **not started**, p40 |
| 7 | `random.Random(seed)` | **silent half FIXED** (`3d3d90a2d`); feature half open, p45 |
| 8 | keyword through a callable value | reproduced, **no ticket exists** |

**Rows 4 and 7 are one mechanism with two failure surfaces** — both qualified
members of a *consumed-only root*. Row 4: nothing answers. Row 7: the **wrong**
thing answered, silently, which is why its silent half was a bug and not a gap.

### The ordering hazard — read this before taking row 4

> **Order: row 8, then the receiver-scan fix, then row 4. Taking row 4 first
> trades a loud refusal for a silent wrong object**, which is worse than today.

Generating `__replace__` on every dataclass **manufactures the exact population
that defeats a first-wins scan**: one name declared by N unrelated classes. It
is the family behind lekkerzeilen blockers 03 and 04. `tsp/shape.py:115`'s
receiver is a dict value in a comprehension — dynamic precisely where this
bites.

### Why TSP is not being worked, and it is a decision not an omission

**Half the remaining board is the `ctypes` seam, and it is blocked on
APPLICATION code that does not exist — not on the compiler.** It is the largest
single population: **10 of 20 failures** (3 direct `ctypes` imports plus 7
downstream of one file).

**The owner parked it, 2026-09-20:** *"for now i rather keep it as is. both
lekkerzeilen and TSP run fine under CPython and Linux. we are good and should
not overcomplicate."*

`tsp/platform/_pxx_backend.py` **does not exist** (verified: a `find` for
`_pxx*` under `/home/neo/tuxspaceprogram` returns nothing). The seam's `else:`
arm imports it, so it is inert today.

**The port is smaller than it was once reported.** The **974-line** figure that
travelled earlier was **a file's line count relayed as a port's cost, and it is
retracted.** The two platform layers are the same design file-for-file, one file
apart: **30 / 67 / 41 / 217** changed lines across four files — *tens to low
hundreds*. A competing set (27/56/40/202) is recorded as **retired**, with the
reason (`grep -c '^[+-][^+-]'` drops blank-line changes).

### ⚠ A live contradiction in the TSP board, raised with its author today

**RESOLVED WHILE THIS PAGE WAS BEING WRITTEN — recorded because the mechanism
is worth more than the incident.** `feature-n-a-pxx-marker-module-...` sat at
**p80, the highest open TSP prio**, with a summary saying `__pxx__` *"MOVES 10
of TSP's 20 remaining failures"* — while the same author's inventory said it
*"moves the wall one line earlier and buys ZERO units"*. Re-verified in TSP's
own source: the seam's `else:` arm imports `_pxx_backend`, which does not
exist, so **the wall moves one line and does not clear.** The author fixed the
summary and **dropped the prio 80 → 45**.

**The nastier half, in the author's own account:** the summary *already
contained its own refutation* three sentences down, in bold. Both readings were
in one field, and **the one that carried was the one at the front with a number
attached** — *"MOVES 10 of 20"* reads as *"clears 10"* to anyone scanning a
queue, where the author meant *"relocates the wall for"*. **A correction placed
below a headline does not correct the headline; it makes the field internally
inconsistent and lets each reader pick.**

**And the count was true of a PREDICTED mechanism rather than a measured one**,
so the field acquired a dependency on the prediction holding. The replacement
is a mechanism sentence that survives either way: *the marker is NECESSARY for
the pxx arm and NOT SUFFICIENT while `_pxx_backend.py` is absent* — with the
condition that would raise it again written in, namely the parked port landing.

**Why this is on a demo close-out at all:** a stale summary carries the prio
into the ranker, so a seat pulling `ready --track N` is sent to the top of a
queue to do work its own author has measured at zero yield.

---

## 5. What the timebox did NOT settle

**Read this section before inferring coverage from the length of the ones
above.**

**Not measured at all:**
- **The cost of reaching a runnable state for uforth or songformatter.** Only
  lekkerzeilen was surveyed.
- **songformatter's packaging**, as a class. Named today, surveyed never.
- **Whether `world/` regeneration works.** It was deliberately not attempted —
  the box is shared and a 15 G rebuild would have spoiled every wall-clock
  measurement anyone else was taking.
- **Bytes read** by lekkerzeilen at run time. The asset survey counted *opens*,
  not volume.

**Measured narrowly, and the narrowness is the point:**
- lekkerzeilen's asset survey is **one code path, one world, one four-second
  run** — 7a's own statement of its limits, and the reason `gauges.lzg` is
  "not required to draw a frame" rather than "unused".
- **Three of today's four fixed demo rows were measured on a binary, not on a
  changelog.** That was deliberate and it is why the 3/3 could be published
  before the ancestry was verified.

**Recorded as absent, so nobody re-derives it:**
- **No ticket for TSP row 8** (`pyvar_callv_kw`, `tsp/historic.py:531`).
- **No ticket for the `threading.Condition` site** at `voice.py:79`, which the
  re-sweep identifies as **one site behind at least three board rows**.
- **Two live `random.Random` tickets** (p45 and p40) with **no `supersedes` or
  `duplicate-of` link**, the p40 one still carrying pre-fix framing. Both are in
  `BOARD.md`.

**Known-false leads, retired today so they do not come back:**
- **974 lines** as the TSP platform port cost — retracted; it was a file size.
- **`wave` landing delivered ZERO units**, measured rather than predicted. Three
  board rows collapsed to **one site**.
- **Implementing `__pxx__` alone buys zero units** while `_pxx_backend.py` is
  absent — per the inventory; see the contradiction above.

---

## 6. One instrument misled the whole fleet today

**Recorded because the cost is invisible: it is the seats who quietly rebuilt
and said nothing.**

`1241020f5` was a **comment-only** change to `compiler/defs.inc`. It made
`gate.sh`'s stale-binary hint fire **fleet-wide**. The hint compares the last
commit touching `compiler/` against the binary's **mtime**, and then announces a
conclusion about **the binary** — so everyone who pulled that commit and gated
saw `STALE BINARY` while holding a byte-identical, perfectly correct compiler.
`frankh-c0` followed it and forced a real recompute, and **got the same binary
back**.

**This is the project's own "every instrument that lies, lies by being correct
about something else", sitting in the one place everybody looks before
gating.** The hint was right about what it measured — a commit timestamp
against an mtime — and wrong about the thing it named. The wording is now
advisory-only and touches no verdict (`frankb-8e`).

**The lesson for tomorrow's release work:** a comment-only commit is exactly the
change nobody expects to move an instrument, which is why this one cost a
fleet-wide rebuild before anyone said it out loud. **If a hint names an artefact,
check what it actually compared before you act on it** — here, `sha256sum` of the
binary against the previous one answers in one command and the hint does not.

---

## 6. What would retire each claim in this document

- **Every PIN row is perishable.** If `stable_linux_amd64/default/pinned` no
  longer hashes to the sha in a row you are reading, **that row describes a
  compiler that is no longer in place.** `repin.sh` refuses to measure unless
  the sha has actually moved, parks superseded rows under their own sha, and
  re-takes. **Do not edit a cell to what you expect** — that is the one change
  nobody re-checks.
- **The 47-of-67 row** is retired by any re-sweep at a newer pxx sha. Carry the
  sha and the `--threadsafe` flag with it, or it is not comparable.
- **The ~168 MB figure** is retired by a second trace over a different code
  path, a different world, or a run long enough to exercise tide.
- **The 1.52× uforth ratio** is retired by a re-run on v414; it was taken on
  `f94c2a7e`.

**And one caution that applies to this whole page:** it is a coordinator's
assembly of four lanes' work. **Where it disagrees with the lane's own
document, the lane's document wins** — it was written by whoever held the
failing tree.
