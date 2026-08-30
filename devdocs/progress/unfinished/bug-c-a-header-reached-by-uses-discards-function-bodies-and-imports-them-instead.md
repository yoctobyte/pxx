---
slug: bug-c-a-header-reached-by-uses-discards-function-bodies-and-imports-them-instead
track: C
type: bug
prio: 55
blocked-by: [bug-a-c-module-attribution-is-sticky-after-a-crtl-impl-pull]
status: unfinished
found: 2026-08-29
found-by: pxx-a5
summary: "A `static`/`static inline` DEFINED in a .h reached through `uses` had its body discarded and became an external, so the program linked a DT_NEEDED on a lib<header>.so that does not exist and died at load. PARTIALLY FIXED 2026-08-30 with the provenance scope term the reverted first attempt was missing (gtk green, .h/.c pair test in the gate). STILL BROKEN for the common shape -- a header that includes <stdio.h>/<string.h> or anything else with a crtl src/*.c sibling above the static -- because CModuleOfTok never resets when an include returns to its parent. Blocked on bug-a-c-module-attribution-is-sticky-after-a-crtl-impl-pull; do not attempt the rest before that lands."
owner: frankC
---

# `uses <header>` throws away the header's function bodies, then imports them

> **PARTIALLY FIXED 2026-08-30, and still open on purpose.** The scope term the
> reverted attempt was missing is now in (`CModuleOfTok(TokPos - 1) < 0` —
> compile the body only when the tokens are not inside a crtl `.c` pull), the
> five gtk tests it broke are green, and the `.h`/`.c` pair test is in the gate.
> **What is still broken is the common shape**: a header that includes
> `<stdio.h>`/`<string.h>` — anything with a crtl `src/*.c` sibling — above the
> static, because the module attribution goes sticky and never comes back. That
> half is `bug-a-c-module-attribution-is-sticky-after-a-crtl-impl-pull`, filed
> against Track A because the table lives in `dbg_filetable.inc`. See "Where it
> stands" below for the measured boundary.

> **HISTORY — one earlier fix was TRIED AND REVERTED.** The shape that
> failed was *"detect a bodied `static` by scanning back over the specifiers
> (`CDeclSawStatic`) and let it fall through to ordinary compilation whenever
> we are in header-import mode."* That is correct for a user's own header and
> it worked there; it is wrong because **the same walk is entered by crtl's own
> module pulls**, and compiling their bodies needs two things the header path
> cannot give (details in the REOPENED section). Do not re-derive that — read
> it. The forward plan is in "What the next attempt needs"; this banner exists
> because a parked ticket that records only the plan reads as untouched.

## Measured, at `62714dc5eb06`

*(That sha does not exist in this repository — checked 2026-08-30. It was named
before the push and the rebase rewrote it, which is the exact hazard
`bug-t-resolve-cites-a-sha-the-rebase-then-rewrites` describes. The measurement
below is unaffected: **re-measured at `5ced3d9a0`** with a HEAD-built
`compiler/pascal26` (fixedpoint `8cc79f5b6f77`, converged after 1 round) —
`zzstat` in a `.h`, called from a `uses`ing `.pas`, still links
`NEEDED libzzhdr3.so` and dies at load with rc 127.)*

Same function, two files. Only the extension differs:

| the file | result |
| --- | --- |
| `zzhdr3.h` — `static int zzstat(void) { return 4242; }` | `ok:`, then **`error while loading shared libraries: libzzhdr3.so`** |
| `zzc.c` — the same function | `ok:`, runs, prints `4242` |

`static inline` — the shape that is in every real C header — behaves the same:
`libzzinl_h.so`, same load failure. An UNCALLED bodied static is harmless: no
`DT_NEEDED`, runs, exit 0. **The damage requires a call.**

## The invariant, asserted in a comment, and false

`cparser.inc`, the header walk:

> *A HEADER declares and defines nothing, so its single registration pass is
> already the whole job*

That reading is right for an FFI surface — `sqlite3.h` declares, `libsqlite3.so`
defines — and it is not true of C headers in general: `static` and
`static inline` definitions are ordinary, and for those there is no library to
import from, because the definition *is* in the header.

The header path takes a function it was handed the body of, drops the body,
marks it external, and synthesises a soname from the header's own stem
(`ConcatThree('lib', LowerCase(cName), '.so', ...)`). Nothing in that chain can
fail, which is why it is silent.

## REOPENED — the first fix was landed and reverted (frankC, 2026-08-30)

Landed as `eefa85d70`, reverted the same night. **It broke five gtk tests**
(`test_c_gtk`, `-types`, `-window`, `-call`, `-gtk3_stock`), all of them Pascal
programs binding gtk3 through a C header. The revert restores all five; verified
by building and running each, not by inference.

**What the fix did:** `CDeclSawStatic` scans backward over the specifiers the
top-level walks skip without recording, and a bodied `static` in header-import
mode was allowed to fall through to ordinary compilation instead of being
externed. For a user's own header that is correct and it worked — the `.h`/`.c`
pair agreed, no invented soname.

**Why it was wrong, and this is the part to keep.** The header walk is not
reached only by the user's `uses <header>`. **crtl's own modules flow through
it too** — `uses gtk` pulls `gtk.h`, which pulls `stdlib.h`, which brings
`lib/crtl/src/stdlib.c` into the same token buffer and the same walk. Compiling
its bodies uncovered two dependencies the header path cannot satisfy, one after
the other:

1. **File-scope `static` VARIABLES are never reserved.** The walk routes every
   declaration to `ParseCSubroutine` and never calls `ParseCGlobalVarDecl`, so
   `pxx_env_load` referencing `pxx_env_buf` / `pxx_env_loaded` failed with
   *"undeclared identifier passed as argument 2 of `__pxx_read`, where a
   pointer is expected"*. Harmless for as long as the bodies were being thrown
   away, because nothing referenced them.
2. **With that patched, the body then needs the Pascal bridge.** The next error
   was *"`__pxx_open` is a pxx-internal runtime symbol and cannot be imported
   dynamically"* — the crtl `.c` two-pass treatment supplies that; the header
   walk does not.

Two deeper dependencies on two successive patch attempts is the signal that the
scope was wrong rather than the patches. Reverted instead of patched a third
time.

## What the next attempt needs

**Scope the body-compilation by PROVENANCE, not by mode.** The distinction that
matters is not header-vs-`.c`; it is *whose tokens these are*. A bodied static
from the header the user actually named should be compiled; one from a crtl
module pulled in behind it should keep today's treatment, because that module
has its own path that already works. `CModuleOfTok(TokPos - 1)` is the existing
mechanism for exactly this question — it is what
`bug-c-static-functions-in-different-crtl-modules-collide` uses to tell two
same-named statics apart — and it is where I would start.

Do not reach for "make the header two-pass like a `.c`". That is a bigger change
that pulls every `uses`d system header's static inlines into compilation, and
the measurement above says the payoff does not need it: an uncalled bodied
static is already harmless.

## The rest of the original analysis (unchanged, still correct)

`bug-a-a-c-include-path-captures-a-pascal-uses-and-emits-a-dynamic-import` is
about a C header *winning a name it should not have won*, and is a different
defect. Fixing the resolver removes the collision for `math` / `netdb` /
`strings` / `png`; a header with a non-colliding name still does this.

Options considered, with the reason option 1 was chosen: **option 2** (refuse a
bodied function in a header) is cheap and honest but breaks any header with a
`static inline` beside the declarations you want, which is most system headers.
**Option 3** (keep the extern, drop the invented soname) turns a load error into
a link error without fixing the wrong answer. **Option 1** (compile the body)
is what `static inline` means and what the C standard's separation of internal
and external linkage already implies — it just has to be scoped to the right
tokens.

## Test material from the reverted attempt

Worth re-creating rather than re-deriving; it is a correct test of the intended
behaviour and it passed for a user's own header:

- `test/chdrstatic/hdrstatic.h` — `static int hs_plain(void) { return 4242; }`,
  `static inline int hs_inline(int v) { return v + 1; }`, an uncalled
  `static inline`, and a bare declaration (the FFI surface, which must keep its
  old treatment).
- `test/chdrstatic/hdrstatic_c.c` — the same two functions.
- A `.pas` per file, both printing `4242` then `42`. **The pair is the
  invariant**: the same source text must behave the same whichever extension it
  is given.
- Plus an assertion that no `DT_NEEDED` on `lib<stem>.so` appears. Write it as a
  negated `grep -q`, never `grep -qv` — the latter passes whenever any line
  fails to match, i.e. every ELF, i.e. it can never fail.

**And add a gtk test to the gate for it.** The five that caught this are Pascal
programs binding a C header; nothing in the C test corpus exercises that path,
which is why the change looked clean on 37 named C tests and a quick gate.

## Where it stands after 2026-08-30 — the measured boundary

The fix compiles a bodied `static` from a `uses`d header **only when the token
is not attributed to a crtl `.c` module**. Measured, varying only what the
header includes above the static:

| the header includes above the static | result |
| --- | --- |
| nothing | **fixed** |
| `"user.h"` (a header with no crtl impl) | **fixed** |
| `<stddef.h>`, `<stdint.h>`, `<stdbool.h>`, `<limits.h>`, `<errno.h>` | **fixed** |
| **`<stdio.h>`, `<string.h>`** and any other header with a crtl `src/*.c` | **still broken** |
| `<stdio.h>` placed *below* the static | **fixed** |

The scope term is *necessary* — without it the walk compiles crtl's own module
bodies, which is what broke five gtk tests and got the first attempt reverted —
and it is *not sufficient*, because `CModuleOfTok` never resets when an include
returns to its parent. `stddef.h` and `stdio.h` differ in exactly one thing:
whether crtl has an impl to auto-pull. Nothing about the static changes.

So the remaining work is not in this lane's files at all. It is
`bug-a-c-module-attribution-is-sticky-after-a-crtl-impl-pull`, which carries the
measurement, the reason the current consumer is not regressed by fixing it, and
the shape to build. **Do not attempt the rest of this ticket before that one
lands** — a third scoping mechanism over the same walk is the failure mode this
ticket has already produced once.

### One methodology note worth keeping

I reached the wrong boundary twice before this table was right.

- First by reasoning about `CModuleOfTok` instead of printing it, which is what
  the debugging playbook says not to do.
- Then by printing it through `IncSmallIntStr`, whose contract is *"small
  NON-NEGATIVE int"* — it renders `-1` as `0`, so the one value that meant "no
  module" was indistinguishable from a real module id. That is
  `differential-probes.md`'s *"a probe that FORMATS its output can answer a
  different question than you asked"*, met in the wild.
- And a whole round of "every include defeats it" measurements was an artifact
  of my own harness: I had named the test program and the test header the same
  stem, so `uses foo` resolved to `foo.pas` — the program itself — rather than
  to `foo.h`. The compiler was reporting a genuine error and I read it as the
  bug under investigation.

Each of those produced a confident, wrong sentence that would have gone into
this ticket. The table above is from the third measurement, with distinct names
and a formatter that can represent the answer.

## Gate

Track C's, plus the `.h`/`.c` pair, plus **at least one gtk binding test**
(`test_c_gtk` needs no X server and reproduces the breakage on its own).

## Log
- 2026-08-30 — **partially fixed** by frankC: the provenance scope term landed
  with the `.h`/`.c` pair test, gtk green. Parked to `unfinished/` blocked on
  `bug-a-c-module-attribution-is-sticky-after-a-crtl-impl-pull`, which is the
  rest of it. Commit f5708eb77.
- 2026-08-29 — filed by pxx-a5, split out of the unit-resolution ticket.
- 2026-08-30 — fixed by frankC (`eefa85d70`), then **reverted** the same night
  after it broke five gtk tests. Reopened with the diagnosis above.
