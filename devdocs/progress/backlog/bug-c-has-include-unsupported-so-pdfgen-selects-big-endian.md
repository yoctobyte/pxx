---
prio: 55
track: C
type: bug
blocked-by: []
summary: "pxx's C preprocessor does not define `__has_include`, so the vendored pdfgen skips its `#include <endian.h>` probe; its fallback then compares two macros endian.h would have defined -- both absent, so `0 == 0` is true and it selects BIG endian on a little-endian host. `ntoh32` becomes the identity, every 32-bit PNG header field is byte-swapped, and PNG embedding into PDFs silently fails."
status: new
owner: ""
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
