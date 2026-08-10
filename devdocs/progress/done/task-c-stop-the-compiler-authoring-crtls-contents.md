---
track: C
prio: 60
type: task
summary: "the compiler hand-authored a 87-name map of crtl's contents and nothing checked the crtl invariant it depends on; generate the map from lib/crtl and lint the invariant"
status: done
---

# Stop the compiler from authoring crtl's contents

- **Type:** task (layering) — **Track C** (`compiler/cparser.inc`) + **Track B**
  (`lib/crtl`, `tools/`)
- **Opened / done:** 2026-08-10, straight after
  [[bug-c-crtl-auto-pull-depends-on-the-pascal-preludes-unit-count]]. Asked for
  directly by the user after that bug's write-up: *"can we split A and B
  cleanly?"*

## The shape problem

Two facts about the A/B boundary, both found while fixing the bug above:

1. **A hand-authored B's data.** `CCrtlHeaderForName` (`cparser.inc`) was an
   if-chain of **87 names across 5 headers**, describing which crtl module
   publishes which libc function. crtl actually publishes **312 functions across
   22 headers**, so it was a 24% sample maintained by hand in a different track's
   file, with nothing to notice drift. Five of its entries (`cos`, `sin`, `tan`,
   `exp`, `scanf`) named functions crtl does not define at all — math.h reaches
   those through `__crtl_`-prefixed macros — so they had been dead for as long as
   they had existed and nobody could tell.

2. **The invariant the auto-pull runs on was unwritten and unchecked.** A crtl
   header's functions must be reachable from that header — its own sibling
   `src/<name>.c`, or a `.c` some header it includes pulls. Violating it does not
   produce a link error: the symbol resolves against **glibc**, in a build whose
   premise is libc-free, where the two agree on the name and not necessarily the
   ABI. It had been violated twice and fixed two different ways
   (`<sys/socket.h>` got a bridge `.c` with a 26-line comment about a guard-order
   trap; `<inttypes.h>` had its functions moved), so the tree held two precedents
   that look nothing alike and no rule.

## Shipped

- **`tools/crtl_reachability.py`** — walks the closure the preprocessor actually
  walks (include edges, sibling auto-pull, and a pulled `.c`'s own includes) from
  every header as a root, and reports any declared function crtl defines but that
  root cannot reach. Verified against both historical occurrences: removing
  `src/inttypes.c` reproduces 4 findings, removing `src/sys/socket.c` reproduces
  15. Clean on the current tree (39 headers, 23 modules).
- **`tools/gen_crtl_map.py`** → **`compiler/crtl_names.inc`** (generated) — the
  name→header map read out of lib/crtl. `--check` fails when stale. Both wired
  into `make lib-test`, which is where crtl lives and where B would introduce
  either fault.
- `CCrtlHeaderForName` now reads the generated table; `CPullCrtlForPrototypes`
  collects an arbitrary header set instead of five fixed booleans.

**Deliberate exclusion:** `pthread.h`. Pulling it without `--threadsafe` is a
hard error by design (`RegisterExternal` refuses `__pxx_p*`), so auto-pulling it
from a hand prototype would turn a working program into a compile error.

## Measured — including the part that is zero

- **Behavioural change on real code: none.** 383 `test/*.c` and 220
  c-testsuite programs, each built with the new compiler AND with
  `stable_linux_amd64/default/pinned`, comparing compile status, full program
  output and exit code: **0 differences**, and **0** programs dropped a dynamic
  dependency. The old 87 names already covered everything the corpora use; the
  missing 225 were a latent authorship hazard, not a live bug. Worth stating
  plainly rather than implying a fix.
- **Improvement is real but only for hand-prototyped C**: a program declaring
  `strtoull`/`strcspn`/`close` by hand and including nothing now links
  **libc-free**, where pinned silently imported all three from glibc.
- **Cost: ~2-3%** on sqlite's 258k-line amalgamation (2.07s → 2.11-2.23s). The
  first cut cost **+25%**, because the sweep can no longer stop early the way
  five fixed headers allowed; a per-bucket length bitmask (`CrtlNameLenMask`)
  rejects almost every identifier in one AND and gives most of it back. Reading
  the token in place instead of via `GetTokenStrFromRaw` was tried and was NOT
  the bottleneck — kept anyway, it is strictly less work.

## Gate

`gate.sh quick` GREEN including the FPC seed canary (which is the one that
matters here — a new `{$include}` and four new routines are exactly the
declaration-order hazard it exists for), `make lib-test`, `make test-core`,
plus the two corpus sweeps above.

## Not done

`CHeaderDefaultSystem` / `CSystemLibStemSelected` (`parser.inc`) still hardcode
which headers and sonames are "system", and `compiler/exdec.inc` is still a
literal copy of `lib/rtl/sysutils.pas`'s exact-decimal core (one of three). Same
class, different files, neither touched here.

## Log
- 2026-08-10 — resolved, commit 25d2628d2.

## User's call on the ~2-3%, 2026-08-10

> "don't worry compiler speed — correctness above all"

So the cost stands and the change is NOT to be reverted for it. Recorded here
because the "Measured" section above offers the revert as an option and a future
session reading only that could take it. Reverting the generated map would put
the compiler back to hand-authoring 87 of crtl's 312 names, which is the actual
defect this closed.
