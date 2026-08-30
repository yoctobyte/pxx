---
prio: 55
track: C
type: bug
blocked-by: []
summary: "pxx's C preprocessor does not define `__has_include`, so the vendored pdfgen skips its `#include <endian.h>` probe; its fallback then compares two macros endian.h would have defined -- both absent, so `0 == 0` is true and it selects BIG endian on a little-endian host. `ntoh32` becomes the identity, every 32-bit PNG header field is byte-swapped, and PNG embedding into PDFs silently fails."
status: done
owner: frankC
---

# `__has_include` unsupported, so pdfgen selects big endian on x86-64

- **Type:** bug — **Track C** (C frontend / `compiler/cpreproc.inc`). Filed
  2026-08-30 from Track B while working
  [[bug-b-imagereader-getsize-returns-a-string-where-reportlab-returns-a-pair]].
- **Not a compat ticket.** Per CLAUDE.md's escape rule, a parity gap that
  produces *silent wrong behaviour* in real compiling code is promoted to a
  normal bug. This one compiles clean, links clean, runs, and returns wrong
  numbers.

## The chain, measured end to end

`lib/vendor/pdfgen/pdfgen.c:162-190`:

```c
#ifdef __has_include            /* pxx: FALSE -- the whole block is skipped   */
#if __has_include(<endian.h>)
#include <endian.h>             /* gcc: taken; defines __BYTE_ORDER/__BIG_ENDIAN */
...
#endif
#endif

#if !defined(__LITTLE_ENDIAN__) && !defined(__BIG_ENDIAN__)
#ifndef __BYTE_ORDER__
#define __LITTLE_ENDIAN__
#elif __BYTE_ORDER__ == __ORDER_BIG_ENDIAN__ || __BYTE_ORDER == __BIG_ENDIAN
#define __BIG_ENDIAN__          /* <-- pxx lands HERE                          */
...
#if defined(__LITTLE_ENDIAN__)
#define ntoh32(x) bswap32((x))
#elif defined(__BIG_ENDIAN__)
#define ntoh32(x) (x)           /* <-- so ntoh32 is the IDENTITY on x86-64    */
```

`__BYTE_ORDER__` is 1234 under pxx (correct), so the `#elif` is reached. Its
left arm is false. Its **right** arm compares `__BYTE_ORDER` against
`__BIG_ENDIAN` — two macros that only `<endian.h>` defines — and an undefined
identifier in `#if` is 0, so it evaluates `0 == 0`: **true**. gcc never reaches
that arm's failure mode because `__has_include` got `<endian.h>` included two
blocks earlier.

Probe (`#ifdef` reports, then pdfgen's exact `#if`):

| | `__has_include` | `__BYTE_ORDER__` | `__BYTE_ORDER` | pdfgen's test says |
| --- | --- | --- | --- | --- |
| pxx | **NOT defined** | 1234 | undefined | **BIG endian** |
| gcc | defined | 1234 | undefined | BIG endian |
| pxx + explicit `#include <endian.h>` | NOT defined | 1234 | **defined** | little endian |
| gcc + explicit `#include <endian.h>` | defined | 1234 | defined | little endian |

Rows 1 and 2 agree — that is the **control**, and it is the important one: with
`endian.h` absent, gcc gets this wrong too. pdfgen's fallback is fragile in
itself. Rows 3 and 4 isolate the single variable: **pxx already includes and
evaluates `<endian.h>` correctly.** The only thing missing is the operator that
decides to include it.

## What it costs, downstream

`pdf_add_image_file` on a valid 8x4 RGB PNG, pxx vs the gcc oracle over the
same `pdfgen.c`:

```
                          gcc                     pxx
rgb8x4.png  (color type 2) rc=0                    rc=-22 "PNG chunk exceeds file: 218103808 vs 74"
cpu.png     (color type 6) rc=-22 unsupported      rc=-22 unsupported          <- control: arms agree
```

218103808 = `0x0D000000` = byte-swapped 13, the IHDR chunk length. The
colour-type check survives only because colour type is a single byte. The
second row is the control: an RGBA PNG that pdfgen genuinely cannot embed
fails identically in both arms, so the first row's divergence is specific, not
a general breakage.

And the sufficiency control — prepend `#define __LITTLE_ENDIAN__ 1` to the same
translation unit under pxx:

```
rgb8x4.png   rc=0 err="(null)"          <- matches gcc exactly
cpu.png      rc=-22 unsupported          <- still matches gcc
```

So the endian selection is the **whole** of it. Nothing else in pdfgen's image
path is wrong under pxx.

## The fix

Support `__has_include` in `compiler/cpreproc.inc`:

- `__has_include` must be *defined* as far as `#ifdef` / `defined()` are
  concerned (gcc and clang both make it visible to `#ifdef`; that is what the
  guard above tests).
- `__has_include(<name>)` and `__has_include("name")` evaluate to 1 when the
  header would be found by the corresponding search, 0 otherwise — evaluated
  during `#if` expression processing, before ordinary macro rules would mangle
  the `<...>` token sequence.
- `__has_include_next` is the sibling; out of scope unless it is free.

## What a fix must assert

- `#ifdef __has_include` is true
- `__has_include(<stdio.h>)` is 1 and `__has_include(<no_such_header_xyz.h>)` is 0
- `__has_include("relative.h")` resolves relative to the including file
- an unfound header inside `__has_include` does **not** error
- the pdfgen differential above: `rgb8x4.png` gives `rc=0` under pxx, matching gcc

## Where it does NOT end

Fixing this makes pdfgen agree with gcc on PNG headers. It does not by itself
make `drawImage` report anything when embedding fails — see
[[bug-b-drawimage-discards-pdfgens-error-and-writes-a-pdf-with-no-image]].

## RESOLVED — 2026-08-30 (frankC)

Opened at HEAD first. It reproduced exactly as filed, control included, and the
diagnosis was right end to end — what follows adds what the implementation
turned up, it does not correct anything.

## What was actually missing

Not so much "`__has_include` is unimplemented" as **the operator needs the
include search, and the include search was not callable**. It lived inline
inside `CPInclude`, addressing the header name as a range `line[a..p-1]` of the
directive being parsed — a shape only a `#include` directive can produce. The
`#if` evaluator has a line and no directive at all.

So: one extraction and one operator.

- **`CPSearchInclude(nm, baseDir, depth, probe)`** — the three-tier search
  (including file's own directory, `-I` roots, host system fallbacks, with the
  `-nostdinc` rule and the crtl anchor) lifted out verbatim and keyed on a
  header NAME. `CPInclude` calls it; so does the operator.
- **`CPExprHasInclude`**, in the `#if` evaluator beside `defined` and
  `__LINE__` — where C23 6.10.1 puts it, and gcc and clang with it.
- **`CPMacroDefined` answers True for `__has_include`**, which is what
  `#ifdef __has_include` — pdfgen's actual guard — tests.

**Sharing the search is the point, not tidiness.** `__has_include` does not
mean "does this file exist on the system"; it means *"would my `#include` of
this name find one"*. pxx's search is not gcc's — no `<>`-vs-`""` split, a crtl
anchor, its own `-nostdinc` rule — so a probe with a search of its own would
answer a question nobody asked, and would drift the first time either copy
changed. One search makes the two answers identical by construction instead of
by review.

`probe` suppresses *reporting* only: a probe that finds a header does not
include it, so the host-fallback warning belongs to the `#include` that follows
(it fires exactly once in the pdfgen build, from the real include), and a probe
that finds nothing is a legitimate 0 rather than the fatal "include file not
found".

## Registering a macro would not have worked

The cheap-looking fix — `CPAddLiteral('__has_include', ...)` so `#ifdef` sees
it — is wrong, and worth recording because it looks right. A registered macro
is also expanded in ordinary text and in the `#if` operand, and `(<endian.h>)`
is not a token sequence macro expansion can survive: a `<`, an identifier, a
`.`, an identifier, a `>` — division and comparison around a macro-expandable
`endian`. That is precisely why the standard makes this an operator evaluated
during `#if` processing rather than a macro.

## Measured

Every value below is from a HEAD-built `compiler/pascal26`, with `pinned`
(pre-fix) as the second arm and gcc as the oracle.

**The operator**, against gcc on the same file — `#ifdef` 1, `defined()` 1,
`<stdio.h>` 1, `<no_such_header_xyz.h>` 0 *and not an error*,
`"chas_include_rel.h"` 1 (the quoted form resolving relative to the including
file). All five identical to gcc; all five differ under `pinned`.

**pdfgen's endian chain, verbatim:**

```
pxx HEAD    pdfgen selects: LITTLE     <- matches gcc
pxx pinned  pdfgen selects: BIG
gcc         pdfgen selects: LITTLE
```

**End to end — `pdf_add_image_file` on a real 8x4 RGB PNG through the vendored
`pdfgen.c`:**

```
                gcc              pxx HEAD         pxx pinned
rgb8x4.png      rc=0 (null)      rc=0 (null)      rc=-22 "PNG chunk exceeds file: 218103808 vs 105"
rgba8x4.png     rc=-22 type 6    rc=-22 type 6    rc=-22 type 6              <- control
```

218103808 = `0x0D000000` = the IHDR length 13 with its bytes reversed. The RGBA
row is the control the ticket asked for: a PNG pdfgen genuinely cannot embed
fails identically in all three arms, so the RGB row's divergence is specific
rather than general breakage.

**All five gtk tests green**, byte-for-byte the same output as `pinned`
(`test_c_gtk`, `-types`, `-window`, `-call`, and `-gtk3_stock` with
`$(pkg-config --cflags-only-I gtk+-3.0)`; without that root `gtk3_stock` fails
identically on both arms — an environment requirement, not a regression).
These are Pascal programs reaching C headers: the population my previous change
broke, and one no C test would have seen.

**The preprocessed output itself is unchanged.** The sharper instrument for an
extraction, and cheaper than any corpus sweep: `--dump-cpp` on four named C
files, HEAD vs `pinned`, 11,832 lines total —
`cmath_constants` (3263), `cstring_batch` (3884),
`test_c_recname_recycled_slot` (3735), `cstrings_bsd` (950) — **byte-identical**
once the two binaries' own install-path prefixes are normalised
(`./compiler/../` vs `./stable_linux_amd64/default/../../`, an artifact of
where each binary sits, not of the change). That is a direct test of the search
extraction at the exact layer it changed, rather than an inference from program
output downstream of it.

**Plus the self-host fixedpoint and `tools/gate.sh quick`.** Naming the
fixedpoint as *insufficient* rather than as evidence: the compiler is written
in Pascal, so compiling it does not execute one line of `cpreproc.inc`. It
proves the edit did not break the build, nothing more. The operator
differential, the pdfgen chain and the gtk set are what argue it is right.

**And what I deliberately did not run.** I started a differential over the
whole C corpus and killed it. The reasoning that reached for it — *"this
touches the include search, which every `#include` goes through"* — is verbatim
the one CLAUDE.md names as the trap that sounds conscientious and is wrong.
Breadth is Track T's, run against the pushed sha; widening here costs ten
minutes and, worse, delays the push, and unpushed work is work T cannot see at
all. The quick tier's C canaries plus the gtk set are the named handful.

## Found while doing this, filed not fixed — two

**`bug-c-has-include-with-a-macro-operand-answers-0`** — `#define HDR <stdio.h>`
then `__has_include(HDR)` answers 0 where gcc answers 1. One divergence of six
forms measured against gcc (the literal `<>` and `""` forms, conjunction,
negation and the ternary all agree). Documented as a known blind spot in
`CPExprHasInclude`'s own comment, because the operand of this operator is not a
token sequence ordinary macro expansion survives and expanding it first is a
different mechanism from the one this ticket needed. Filed as a `bug-` rather
than compat: we do not *reject* the form, we answer it wrongly and silently,
which is the escape rule. Low prio because the reach is small — pdfgen, zlib,
lua and sqlite all use the literal forms.

**`bug-c-an-include-nested-deeper-than-16-is-silently-dropped`** — `CPLoadInclude`
and `CPIncludeLength` are `case depth of 0..15` with no `else`, while the
nesting guard errors at `MAX_CPREP_INCLUDES = 128`. Past depth 15 the load is a
no-op and `CPIncludeLength` returns an **unset function Result**, so the 17th
nested header vanishes with no diagnostic — `LEVEL16` came back 0 where gcc
says 16. Present on `pinned` too, so it is not new. It surfaced here only
because the probe had to know which depths are safe to load at, which is why
`CPExprHasInclude` answers 0 above depth 15 rather than reading that unset
value.

## Test

`test/chas_include.c` + `test/chas_include_rel.h`, wired into `test-core`
beside the other C-frontend regressions. It carries pdfgen's endian block
verbatim, because the operator working in isolation is not the property that
was missing — *this chain reaching the right arm* is. Validated in both
directions: identical to gcc at HEAD, and all six lines differ under `pinned`.

## Where this does NOT end, unchanged from the ticket

Making pdfgen agree with gcc on PNG headers does not make `drawImage` report
anything when embedding fails — `bug-b-drawimage-discards-pdfgens-error-and-
writes-a-pdf-with-no-image` is still open, and is Track B's.

## Log
- 2026-08-30 — fixed by frankC, commit PENDING-COMMIT.
- 2026-08-30 — resolved, commit PENDING-COMMIT.
