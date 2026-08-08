---
track: N
prio: 45
type: bug
summary: "ALL 13 Forth 2012/ANS word sets byte-identical to CPython and ENROLLED in test-uforth (17/17 corpora) as of 2026-08-08. Four separate causes, four fixes: a gapped closure-bridge arity table; a borrowed return read as owned; pop(i) leaving a live alias in the slot it vacated; a redefined nested def that never rebound its name. `make test-uforth`'s 10 corpora do NOT include core.fr or any of these, so none of it is gated."
status: done
---

# uforth's ANS word-set suite: 13 of 13 identical, and gated

uforth ships the **Forth 2012 test suite** (`tests/`, from
forth2012-test-suite 0.15.0) — the John Hayes ANS tester plus per-word-set
programs. `tests/runtests.fth` is its master runner. This is far more thorough
than the `_drv_*.fth` files, and it was NOT being measured: the drivers reach
only 9 of the suite's files, and `core.fr` is not among them.

Measured 2026-08-08, each word set run under a generated driver
(`prelimtest` + `tester.fr` + `utilities` + `errorreport` + the suite), pxx's
binary against CPython running the same `uforth.py`:

| word set | verdict |
| --- | --- |
| `core.fr` (Hayes ANS core) | **IDENTICAL** |
| `coreplustest.fth` | **IDENTICAL** |
| `doubletest.fth` | **IDENTICAL** |
| `exceptiontest.fth` | **IDENTICAL** |
| `facilitytest.fth` | **IDENTICAL** |
| `localstest.fth` | **IDENTICAL** |
| `memorytest.fth` | **IDENTICAL** |
| `searchordertest.fth` | **IDENTICAL** |
| `stringtest.fth` | **IDENTICAL** |
| `coreexttest.fth` | **IDENTICAL** — was SEGFAULT, fixed 2026-08-08 |
| `blocktest.fth` | **IDENTICAL** — was SEGFAULT, fixed 2026-08-08 |
| `toolstest.fth` | **IDENTICAL** — was HANG, fixed 2026-08-08 |
| `filetest.fth` | **IDENTICAL** — was wrong output, fixed 2026-08-08 |

`runtests.fth` end to end: pxx dies at line 71 of CPython's 253, inside
`coreexttest` — after correctly printing "End of Core word set tests" and "End
of additional Core tests". The core word set really does pass.

## Three distinct failures, not one — confirmed, and they really were three

The guess in the original filing was that coreext and block shared a cause
because both died at output line 43. They did not. Each was bisected to its own
minimal repro:

- **coreext — FIXED** (`fix(N): give the closure call bridge an exact type per
  arity, 0..32`). Not the `.(` family at all: `MARKER` builds a `restore`
  closure with 1 own parameter + 11 captures, and `pyboundfn_callvn`'s table of
  function types had GAPS (no 10, no 12, nothing above 13) and rounded UP to the
  next type it had. That segfaults rather than degrading. Regression test:
  `test/test_nilpy_escaping_closure_many_captures.npy`, captures 8..20.
- **block — FIXED** (`fix(A): a variant-returning call is not an owned object
  reference`). `flush_blocks` writes through
  `self._ensure_block(blk) -> bytearray`, and that borrowed return was read as
  owned, so the block store's buffer was freed the moment the helper returned:
  [[bug-nilpy-a-borrowed-object-returned-through-a-call-is-over-released]].
  **Timing note for whoever re-measures this:** blocktest is the slow one —
  244s under pxx against CPython's 82s. A 180s timeout reads as a HANG and cost
  this session one wrong "still broken" call. Give it 600s.
- **tools — FIXED** (`fix(N): pop(i) must clear the slot it vacates, not leave
  a live alias`). It hung rather than crashing and was rightly not assumed to
  share a cause — it did not: `CS-ROLL`'s `pop(index)` shifted the tail with a
  raw slot copy, so the next `append` released a live element and a
  control-flow entry became an empty tuple mid-compile.
  [[bug-nilpy-list-pop-index-destroys-a-surviving-tuple-element]]. Also NOT the
  same as block's over-release, which was the standing hypothesis: the ARC fix
  landed first and changed nothing here.
- **file — FIXED** (`fix(A): a nested def REDEFINED in one scope must rebind
  the name`). Both `w_include` defs registered under `build_base_vm.w_include`,
  so the second was unreachable and pxx ran the first.
  [[bug-nilpy-uforth-file-word-set-include-redefinition]]. That ticket's SECOND
  finding — `1+` undefined inside an INCLUDEd file — turned out not to be a
  separate bug at all: it was downstream of running the wrong INCLUDE, and went
  away with it. Worth remembering as a pattern — two symptoms from one wrong
  binding read as two bugs.

Swept end to end after all four fixes: **every one of the 13 is byte-identical.**
The gating gap below is closed too: `test-uforth` now generates a driver per
word set into the uforth checkout, runs all 13 differentially, and cleans up —
17/17 corpora, measured end to end. Drivers are generated rather than committed
so the corpus can never again depend on files that exist on one box.

**blocktest costs ~240s under pxx against CPython's ~80s** and is essentially
the entire ~6 minutes this adds; that belongs to whoever places test-uforth in
a tier.

Four failures, four unrelated causes. The original filing guessed coreext and
block shared one because they died at the same output line, and guessed file's
two symptoms were two bugs. Both guesses were wrong in the same direction:
**where the failures group is not evidence about where the causes group.**

## The gating gap this exposes

`make test-uforth` now runs 10 corpora differentially, but they are the
`_drv_*.fth` drivers plus the RC4 `.for` files — **`core.fr` and the other ANS
word sets are not among them**, because uforth ships no driver for them. So the
single most valuable suite in the tree passes and is ungated.

Adding them needs a driver per word set. Generating one into a scratch dir does
not work as-is: `INCLUDED` resolves relative paths through uforth's own
`resolve_path`, so a driver outside the uforth tree cannot reach
`prelimtest.fth`. Either generate the drivers INTO the uforth checkout (and
clean up), or ask uforth for permanent `_drv_core.fth`-style files — the latter
is cheap and is how the existing seven got there.

Pairs with [[feature-t-enroll-uforth-in-the-tiers]]: enrolling a corpus that
omits the core word set would lock in a flattering number.

## Gate

All 13 word sets byte-identical to the CPython run, `runtests.fth` end to end
identical, and the passing ones added to `UFORTH_CORPUS` so they stay that way.

## Log
- 2026-08-08 — resolved, commit PENDING-COMMIT.
