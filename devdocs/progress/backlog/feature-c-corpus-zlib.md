---
prio: 60
blocked-by: [bug-c-gzgetc-fnlike-macro-call]
---
# C corpus step 2: zlib v1.3.1 bring-up

- **Type:** feature (C frontend validation) — Track A/C. Sub-step of
  [[feature-c-corpus-expansion]].
- **Status:** in progress 2026-07-06 — vendored + runner landed, oracle green,
  2 compiler blockers filed. Not yet passing.
- **Workload class:** bit-twiddling, huffman tables, CRC loops, unsigned
  saturation, fn-ptr dispatch — different muscle than lua/sqlite.

## Done
- Vendored via `tools/install_lib_candidates.sh zlib` (madler/zlib commit
  51b7f2abdade71cd9bb0e7a373ef2610ec6f9daf = v1.3.1; gitignored, PROVENANCE.md).
- `test/zlib/runner.c` — unity build: crtl units + the 15 zlib TUs + zlib's own
  `test/example.c` (self-checks compress/inflate/gzio round-trips, exit(1) on
  mismatch).
- **Oracle GREEN:** gcc build of the same zlib sources + example.c runs clean,
  exit 0, 7 round-trip lines ("uncompress(): hello, hello!" … "inflate with
  dictionary: hello, hello!"). This is the byte-compare target.
- `make test-zlib` target (skips if tree absent; NOT in `make test` — 3rd-party).
- Each zlib TU group compiles alone under pxx; the failures are specific
  interactions/constructs below.

## Blockers
1. ~~**bug-c-typedef-name-as-uninitialized-local**~~ — **FIXED 2026-07-06**
   (commit 0e2740ee): shadowed-typedef-name-as-local now parses; `trees.c` clears.
2. **[[bug-c-gzgetc-fnlike-macro-call]]** (open blocker) — `crtl + zlib.h +
   example.c` fails:
   `Expected: ), but got: (Kind: 74) near: gzgetc >>> file`. example.c calls the
   `gzgetc(file)` macro that zlib.h defines to inline the fast path (expands to a
   comma/ternary expr referencing gzFile internals). Not yet reduced to a minimal
   repro — do that first in the fix session (candidates: function-like macro
   whose body is a parenthesized comma-expression; or the `(gzgetc)(file)`
   parenthesized-function-name call in the fallback arm). File as its own
   bug-c-* ticket once isolated.

## Gate
Both blockers fixed → `make test-zlib`: pxx runner output byte-identical to the
gcc oracle, exit 0. Then graduate to a fuller vector set (minigzip round-trip)
and cross targets. Bonus: cross-check against the Pascal zlib in lib-test.
