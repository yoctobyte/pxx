---
slug: bug-c-a-header-reached-by-uses-discards-function-bodies-and-imports-them-instead
track: C
type: bug
prio: 55
status: backlog
found: 2026-08-29
found-by: pxx-a5
summary: "A `static`/`static inline` function DEFINED in a .h reached through `uses` has its body discarded and becomes an external, so the program links a DT_NEEDED on a lib<header>.so that does not exist and dies at load. The identical function in a .c compiles and runs. REOPENED 2026-08-30: a first fix was landed and REVERTED -- it was correct for a user's own header and wrong for the crtl modules that reach the same walk. Read the reopen section before attempting it again."
---

# `uses <header>` throws away the header's function bodies, then imports them

## Measured, at `62714dc5eb06`

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

## Gate

Track C's, plus the `.h`/`.c` pair, plus **at least one gtk binding test**
(`test_c_gtk` needs no X server and reproduces the breakage on its own).

## Log
- 2026-08-29 — filed by pxx-a5, split out of the unit-resolution ticket.
- 2026-08-30 — fixed by frankC (`eefa85d70`), then **reverted** the same night
  after it broke five gtk tests. Reopened with the diagnosis above.
