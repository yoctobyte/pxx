# Resume after the RAM reboot — 2026-09-19 ~17:00

The owner powered the box down to install more RAM. Every seat reported in.
**This file is the coordinator's handover only** — its context does not survive
a reboot. Where a seat wrote its own note, this file POINTS at it and does not
restate it; two copies drift and the ticket is where someone will already be
looking.

## Priority after reboot

1. **frankh-3f — Track N, That Space Program under NilPy.** The only seat with
   an OUTSTANDING VERDICT: it started a full `test-nilpy` tier
   (`PXX_ALLOW_FULL_SUITE=1`, because the red got past the quick gate) that had
   not reported at shutdown, and the commit says so. **First action: re-run that
   tier.** If green, the TSP census can wait behind anything more urgent — its
   own self-assessment is "medium", and it is the reason to resume early rather
   than the work itself.
2. **Route 2 (pxx links its own objects) — DELIBERATELY UNOWNED.** Two of five
   stages are in: `8c66a2053` ELF64 object reader, `98b42be27` symbol-table
   merge. **The handoff note is in the TICKET** —
   `feature-a-pxx-cannot-link-its-own-objects-...` — plus `b4104386a`. Stage 3
   is section layout; the first decision is whether to concatenate per section
   NAME or per section TYPE. frankb-56 left ownership unheld on purpose and
   wrote everything down; this is takeable by any A seat.
3. **`bug-t-armed-autopin-has-refused-62-consecutive-times-...`** (T, p85,
   `backlog-tools/`, status backlog, unowned). Raised by neo-a2 with evidence
   rather than opinion, and it needs the owner (see below).
4. **`bug-n-a-same-named-rtl-unit-shadows-both-a-relative-import-and-a-mimic-
   shim`** (N, p85, `backlog-nilpy/`, new, unowned) — neo-a2 measured the
   case-insensitive RTL-unit binding mechanism this morning and this is its live
   half.
5. **franks-ee — Track C.** Holds NOTHING; the p60 block-scope `extern` landed
   green as `09743b072` and is in `done/`. `next --track C` names the p40
   thread-local seam, and **franks-ee explicitly argues against ranking its own
   lane first**: three defects closed on that seam in a row, what remains is a
   per-thread allocator change entangled with Route 2's area sizing, and it is
   bug-fix work against a standing application-focused instruction. Take its
   word for that.

Owner's own seats, self-directed, not ranked: `tuxspaceprogram-6e` (stopped
clean, main at `6caa5f2`, waiting on his feedback on the `./menu.sh`
Voyager/Starlink runs), `lekkerzeilen-c8` (see below), `regenmeter-32`.

## NEEDS THE OWNER — two things, neither actionable by an agent

- **lekkerzeilen `main` is 235 commits ahead of origin.** Six are
  lekkerzeilen-c8's; the other 229 predate its session and it has not read them
  and will not vouch for them. Pushing publishes all 235 to
  `git@github.com:yoctobyte/lekkerzeilen.git` — outward-facing, not undone by
  deleting anything after. It correctly refused, and a relayed wind-down
  instruction is not authorisation. **The number to put in front of him is 235,
  not the word "push".** Its own notes: `devdocs/perf/RESUME-HERE.md` at
  `3f81524`. Its open item 1 is the `assets/facades.lzx` decision — 6.8 MB,
  generated, unregenerable from anything committed, and a question he has never
  been asked. Not at risk from the reboot.
- **No pin for 45 hours** (v411, `8d9d69bdc`, 2026-09-17 19:42 — measured, not
  quoted). `make pin` is his call. neo-a2's argument is evidence-based: twice
  today a result depended on the PIN and not on HEAD, because `lib/rtl/pil.pas`
  is built by whatever compiler the user has and the PIL differential runs
  against `$(PXX_STABLE)`. Track B validates against a compiler that is days
  behind the one it writes for, and the failure is the quiet kind.
  **CAUTION ON THAT TICKET'S OWN NUMBER:** its title says *99 hours* and it was
  created 2026-09-11 — v411 has been pinned since, so the headline is eight days
  stale. The mechanism is live; the number in the title is not.

## Corrections the coordinator made tonight and must not repeat

- **`git merge-base --is-ancestor A B` is true when A is an ancestor of B.**
  Work is covered by a tier iff the **WORK** sha is an ancestor of the **TIER**
  sha. Ran backwards on 2026-09-19 and reported a breadth gap closed when it had
  not. Sanity-check the direction on a known-older sha before quoting coverage.
- **A reboot does NOT take local commits with it.** `.git` is on ext4, not
  tmpfs; installing RAM does not touch the disk. The real rule is narrower and
  CLAUDE.md states it correctly: the tree survives, but the NEXT session has no
  idea the work is there. The coordinator relayed "commit and push or lose it"
  to every seat, which overstated the urgency — and in lekkerzeilen's case that
  framing pushed toward a decision that should be taken calmly. `/tmp` is the
  real casualty and that warning was right.
- **The owner did NOT commit the lekkerzeilen tree on 2026-09-19 — the
  `lekkerzeilen-c8` session did, at his prompting.** He asked why it had not
  committed and said he commits regularly to track progress and find
  regressions; it split ~2100 uncommitted lines into four coherent commits, plus
  two since. The STATE previously recorded was right; only the actor was wrong.
  Ask that session what the split was based on.
- **The new NilPy red was named wrong on the way through.** twatch reported
  `test_nilpy_str_line_continuation.npy`; the failing job's file is
  `test_nilpy_line_continuation.npy` — both exist, and the coordinator tested the
  wrong one and reported "does not reproduce". frankh-3f reproduced it at HEAD
  every time and fixed it: `d90ddd2b7`. **Both files PASS at HEAD now**
  (verified after rebuild, `a6a2a1cc2278`). Cause was its own `f646378ff` —
  deferring a subclass of a deferred class caught `class Base(object)`, and an
  override then widened an already-compiled base method's result. A sole
  `object`/`Generic[...]`/`Protocol[...]` base now counts as no parent.
  Consequence filed: `bug-n-an-override-changing-the-result-type-in-a-late-laid-
  out-class-is-refused` (p35) — one shape that ran on pinned is now refused, and
  pinned v411 segfaults on it.

## Unowned and unticketed

- **ctypes under pxx is unstarted and has NO ticket.** Design is
  `devdocs/dev/ctypes-under-pxx.md` (`e26764d09`); the owner asked about it
  directly tonight. Measured at shutdown: no `mimic_ctypes`, no `CDLL`, no
  `c_uint32` in `lib/` or `compiler/`. **Hazard, and it is why a partial start
  is worse than none:** both lekkerzeilen and TSP select their backend with
  `try: import ctypes / except ImportError: _pxx`, which NilPy resolves at
  COMPILE time — so the moment an importable `mimic_ctypes` exists, both apps
  flip onto the CPython arm silently, because the import succeeding IS the
  signal. Land it whole or not at all.
- **`struct.calcsize("P")` is refused** (`bad char in struct format: P`), so
  after tonight's `sys.maxsize` fix (`500db8497`) the target pointer width has
  exactly one working answer, not two.
- `sys.platform` answers `linux` on every target — correct today only because
  `--list-targets` has no Windows target to get it wrong on.

## State at shutdown

Open regressions **6**, the standing set: five carry twatch's own *"bad touches
NO buildable file: it is the tested upper bound, not a lead"*, one is pin-built.
`deadlock_diag` cleared on its own (`0c673f9e4`). `/tmp` 13% bytes, 2% inodes —
**and everything under it is gone after the power cycle.**
