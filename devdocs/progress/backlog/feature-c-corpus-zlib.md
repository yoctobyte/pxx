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


## 2026-07-07 progress — parse cleared, now a link-stage symbol gap
gzgetc function-like-macro parse blocker RESOLVED (bug-c-gzgetc-fnlike-macro-call:
`(name)(args)` paren-function-name call). zlib example.c now parses, compiles and
LINKS the runner. `make test-zlib` next blocker: runtime
`undefined symbol: gz_error` — a zlib-internal function not being compiled/linked
into the runner (a zlib .c TU missing from the build set, or an internal symbol
not emitted). Next: find which zlib TU defines gz_error (gzlib.c) and why the
runner build omits it; then re-diff vs the gcc oracle (8 lines expected).


## 2026-07-07 — 4/8 output lines now match (was parse-blocked)
Fixed a cascade of general string-literal-decay + linkage bugs, each advancing
the runner (all landed on master with regressions b171-b174, self-host
byte-identical, c-conformance 195/0):
- `(gzgetc)(g)` paren-function-name call (bug-c-gzgetc-fnlike-macro-call)
- gz_error dynamic-import (guardless gzguts.h re-externalized a defined fn)
- `return "literal"` not char*-decayed (zlibVersion check)
- `"literal"[i]` 0-based single-byte indexing (uncompress/inflateInit version)
Runner now passes: version line, uncompress(), gzread(), gzgets().
NEXT BLOCKER: `inflate error: -2` (Z_STREAM_ERROR) at inflate()/large_inflate/
inflateSync/inflate-with-dictionary. Z_STREAM_ERROR from inflate = bad state/
stream params — deeper (inflate's windowBits/state machine, likely a struct
layout or function-table issue, not another string decay). Isolate: minimal
inflateInit2+inflate of the fixed 'hello' stream vs gcc; instrument inflate()'s
early Z_STREAM_ERROR guards (strm/state NULL, window size).


### inflate -2 sharpened (2026-07-07)
Isolated with a minimal deflate+inflate harness: inflateInit=0 (state non-null),
then inflate returns Z_STREAM_ERROR (-2) MID-STREAM at total_in=7 under the
byte-at-a-time buffers (avail_in=avail_out=1). uncompress() works because it
inflates in ONE call and never suspends; test_inflate forces suspend/resume every
byte. So the bug is in inflate's multi-call SUSPEND/RESUME path — the LOAD/RESTORE
of state->{hold,bits,next,put,have,left} across calls and the NEEDBITS/PULLBYTE
goto-driven resume. Likely a pxx codegen issue in inflate.c's large single
function (local caching of state fields, or a goto/label save), not a frontend
string bug. Next: instrument inflate()'s mode switch to log where mode goes
invalid on the 2nd/3rd call; compare state->hold/bits save-restore vs gcc.


## 2026-07-07 — 6/8 lines; inflate WORKS (COPY macro leak fixed)
The inflate -2 was NOT a codegen bug: zutil.c includes gzguts.h, whose private
`#define COPY 1` is never #undef'd, and in pxx's single-TU unity build it
macro-replaced inflate.h's `COPY` enum constant (16195) with 1 → inflate()
corrupted state->mode after a STORED block and returned Z_STREAM_ERROR under
byte-at-a-time buffers. Real zlib compiles each .c separately so never sees it.
Fixed in test/zlib/runner.c: `#undef COPY` before inflate.c (gzguts.h is
guardless so gz*.c re-define it). Diagnosis method: bisected mode via printf at
inf_leave → mode went 16193(STORED)→1 at `state->mode = COPY`; PROBE showed
`#ifdef COPY` true = a leaked macro; only COPY collides (gzguts vs inflate enum).
GENERAL LESSON: pxx's no-linker unity C build leaks every private macro across
all files; a porter must #undef colliding names (or pxx would need per-file macro
scoping — big preproc change). Now passes version/uncompress/gzread/gzgets/
inflate/large_inflate.

NEXT BLOCKER: `inflateSync error: -3` (Z_DATA_ERROR). inflateSync returns -3 when
the 00 00 FF FF flush marker isn't found (state->have != 4). syncsearch is
correct; the marker comes from test_flush's `deflate(Z_FULL_FLUSH)` — so suspect
the DEFLATE Z_FULL_FLUSH output (deflate.c/trees.c flush path), not inflate.
Also re-check for further gzguts/other private-macro collisions in deflate.c
(none found for inflate enum, but deflate has its own constants). Then
inflate-with-dictionary (blocked behind sync).
