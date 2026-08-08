---
track: N
prio: 45
type: bug
summary: "The FULL Forth 2012/ANS suite measured per word set: 10 of 13 byte-identical to CPython (coreext FIXED 2026-08-08 — the closure bridge's arity table had gaps). 3 open, each with its own ticket and a minimal repro: block, tools, file. `make test-uforth`'s 10 corpora do NOT include core.fr or any of these, so none of it is gated."
---

# uforth's ANS word-set suite: 10 of 13 identical, 3 open

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
| `blocktest.fth` | **SEGFAULT** (rc 139, 43 of 124 lines) |
| `toolstest.fth` | **HANG** (rc 124 = timeout, 43 of 47 lines) |
| `filetest.fth` | wrong output (both exit 0, same line count) |

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
- **block** — `1 BLOCK DROP UPDATE` then `FLUSH` segfaults.
  `flush_blocks` writes through `self._ensure_block(blk) -> bytearray`, and a
  borrowed object returned out of an annotated function is over-released:
  [[bug-nilpy-a-borrowed-object-returned-through-a-call-is-over-released]]
  (root cause measured — `IRNodeYieldsOwnedRef` reads a container index, which
  is an AN_CALL, as an owned +1).
- **toolstest HANGS** rather than crashing, and rightly was not assumed to share
  a cause: `CS-ROLL`'s `pop(index)` leaves the surviving tuple as `()`.
  [[bug-nilpy-list-pop-index-destroys-a-surviving-tuple-element]].
- **filetest** is the already-filed
  [[bug-nilpy-uforth-file-word-set-include-redefinition]] (the ANS FILE word
  set: two same-named `w_include` nested defs, and `1+` unresolved inside an
  INCLUDEd helper).

This ticket stays open as the umbrella: it closes when all 13 word sets are
identical AND enrolled, which needs the three above plus the driver work below.

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
