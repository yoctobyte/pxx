---
track: N
prio: 45
type: bug
summary: "The FULL Forth 2012/ANS suite measured per word set: 9 of 13 byte-identical to CPython, 4 open — coreext SEGFAULTS, block SEGFAULTS, tools HANGS, file differs. `make test-uforth`'s 10 corpora do NOT include core.fr or any of these, so none of it is gated."
---

# uforth's ANS word-set suite: 9 of 13 identical, 4 open

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
| `coreexttest.fth` | **SEGFAULT** (rc 139, 43 of 93 lines) |
| `blocktest.fth` | **SEGFAULT** (rc 139, 43 of 124 lines) |
| `toolstest.fth` | **HANG** (rc 124 = timeout, 43 of 47 lines) |
| `filetest.fth` | wrong output (both exit 0, same line count) |

`runtests.fth` end to end: pxx dies at line 71 of CPython's 253, inside
`coreexttest` — after correctly printing "End of Core word set tests" and "End
of additional Core tests". The core word set really does pass.

## Three distinct failures, not one

- **coreext / block segfault** at the same place in the output (43 lines), which
  is right after "Test utilities loaded". The first missing CPython content in
  coreext is its `.(`, `.R` and `U.R` output block — worth checking whether this
  is the `.(`-family again now that
  [[bug-nilpy-uforth-dot-paren-prints-nothing]] is fixed, or a second cause
  wearing the same coat.
- **toolstest HANGS** rather than crashing. A hang is a different bug class from
  a segfault and should not be assumed to share a cause.
- **filetest** is the already-filed
  [[bug-nilpy-uforth-file-word-set-include-redefinition]] (the ANS FILE word
  set: two same-named `w_include` nested defs, and `1+` unresolved inside an
  INCLUDEd helper).

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
