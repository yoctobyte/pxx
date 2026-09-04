---
slug: bug-c-offsetof-in-a-static-array-initializer-folds-to-zero-silently
title: "offsetof in a static ARRAY initializer folds to 0, silently, and zeroes every other element with it"
track: C
prio: 75
type: bug
status: backlog
created: 2026-09-04
found-by: franks-ab
owner: ""
blocked-by: []
summary: "MEASURED on the PINNED v403 compiler. `offsetof(T, m)` -- i.e. `&(((T*)0)->m)` -- evaluates to the member's offset in an expression and in a static SCALAR initializer, but to ZERO inside a static ARRAY initializer, with no diagnostic of any kind. Worse, ONE such element zeroes the WHOLE initializer: `{ 5, offsetof(struct inner, b), 9 }` yields `0 0 0`, so plain literals that have nothing to do with offsetof come out wrong too. It is not about nesting (a flat member path fails identically), not about constness (a mutable static fails identically), and not about constant folding in general (`sizeof` and `3+4` in the same array are correct, and `(unsigned long)((char*)0 + 5)` is correct -- only the address-of-member-of-null form fails). Found by booting the pxx-built busybox as PID 1: `uname -a` printed `Linux` eight times because busybox indexes `struct utsname` through `static const unsigned short utsname_offset[] = { offsetof(...), ... }` (coreutils/uname.c:113), which came out all-zero, so every field read back as sysname. The 621-case busybox corpus cannot see this class at all -- it invokes every applet only with `--help`."
---

# offsetof in a static array initializer is 0

## The measurement

Pinned v403 `c31d03b2`, x86-64, against gcc on identical source.

| shape | gcc | pxx | |
| --- | --- | --- | --- |
| `static const unsigned short a[] = { offsetof(S, n.a), .n.b, .n.c, .tail }` | `0 8 16 24` | `0 0 0 0` | **wrong** |
| same, `unsigned long` | `0 8 16 24` | `0 0 0 0` | **wrong** |
| same, FLAT member path (no nesting) | `0 8 16` | `0 0 0` | **wrong** |
| `static unsigned short a[] = {...}` (mutable) | `8` | `0` | **wrong** |
| `static const unsigned short mix[] = { 5, offsetof(S,b), 9 }` | `5 8 9` | `0 0 0` | **wrong, and it took the literals with it** |
| `static const unsigned short a[] = { sizeof(S), 3+4 }` | `24 7` | `24 7` | ok |
| `static const unsigned long a[] = { (unsigned long)((char*)0 + 5) }` | `5` | `5` | ok |
| `static const unsigned short s = offsetof(S, b)` (SCALAR) | `8` | `8` | ok |
| `const unsigned short loc[] = { offsetof(S,b) }` (LOCAL) | `8` | `8` | ok |
| `printf("%u", (unsigned)offsetof(S, n.b))` (EXPRESSION) | `8` | `8` | ok |

`sizeof(struct inner)` and `sizeof(struct outer)` are correct in every build, so
the LAYOUT is right — it is the initializer that loses it.

## What the boundary says, and what it rules out

Four hypotheses died in the measurement above, so do not spend time on them:

- **not nesting.** `offsetof(struct inner, b)` — one level, no dot path — is
  wrong in exactly the same way. My first hypothesis was `offsetof` with a
  dotted member path, and the flat row killed it.
- **not constness.** A mutable `static` array fails identically.
- **not constant folding in general.** `sizeof` and `3+4` fold correctly in the
  same array, in the same declaration.
- **not null-pointer arithmetic.** `(unsigned long)((char*)0 + 5)` gives 5.

What is left is narrow: **the address of a MEMBER through a null pointer,
`&(((T*)0)->m)`, reaching an AGGREGATE (array) static initializer.** The scalar
and expression contexts get it right, so a working evaluator exists — this is
the second path in the sense of `normalise-dont-special-case.md`, and it is the
one that is broken.

**The `mix` row is the one to fix first if the two turn out to be separable.**
An element the initializer evaluator cannot handle does not fail, and does not
fail *locally*: it silently zeroes the entire initializer, so `5` and `9` come
back as `0`. That converts one unsupported construct into unbounded wrong data
in the same declaration.

## Repro

    struct inner { char a[8]; char b[8]; };
    static const unsigned short off[] = { 5, offsetof(struct inner, b), 9 };
    int main(void) { printf("%u %u %u\n", off[0], off[1], off[2]); }   /* 0 0 0, want 5 8 9 */

    gcc -O1 -o oracle x.c && ./oracle                        # the oracle
    ./stable_linux_amd64/default/pinned x.c out && ./out

`offsetof` is `lib/crtl/include/stddef.h:12`,
`#define offsetof(type, member) ((size_t)&(((type *)0)->member))` — the same
spelling the failure reproduces with when written out by hand, so this is not a
macro-expansion problem.

## Where it was found, and why nothing caught it

Booting the pxx-built busybox as PID 1 under qemu-system
([[feature-b-a-bootable-image-with-the-busybox-userland-on-it]]). `uname -r`
printed `Linux`; `uname -a` printed `Linux` eight times. `coreutils/uname.c:113`
walks `struct utsname` through

    static const unsigned short utsname_offset[] = {
        offsetof(uname_info_t, name.sysname), ... };

so with every offset 0 each field read back as `sysname`. **A plausible wrong
value, not a crash**, and the applet exits 0.

**The 621-case busybox corpus is structurally unable to see this**, and that is
worth stating precisely rather than as a complaint: `run_dispatch_cases` invokes
each of the 258 applets as `applet --help` and as `busybox applet --help`, twice
each, which is 516 of the 621 cases. `--help` prints a string literal. No amount
of widening the APPLET list reaches this class; only running applets with real
arguments does. See the note at the end of
[[feature-b-a-bootable-image-with-the-busybox-userland-on-it]].

## Blast radius

`offsetof` in a static table is an ordinary C idiom — option tables, field
descriptors, serialisation maps, driver tables — and it is used precisely where
a zero is indistinguishable from a valid first-member offset. Any such table
compiled by pxx today reads element 0 for every entry, silently.

Filed from Track B, which cannot fix it (it builds with `$(PXX_STABLE)` and does
not rebuild the compiler).

## Re-measured 2026-09-04 — NOT fixed at HEAD, and the mechanism is worse than "folds to zero"

Asked to weigh this as a re-pin argument, the coordinator measured both ends.
**Not fixed at HEAD** (`44adaa79a`, compiler sha256 `6b4e2ed156d6`, from a real
`converged after 1 round(s)` build) — identical behaviour to pinned v403. So it
is **not** an argument for a re-pin: a re-pin would carry the same defect.

**The array is TRUNCATED, not merely zeroed.** Against the gcc oracle:

```
                       pxx HEAD      gcc
static int ofs[] = { 5, offsetof(struct S,b), 9 };
  sizeof(ofs)          4              12
  elements             1              3
  ofs[0]               0              5

static int szo[] = { 5, sizeof(struct S), 9 };
  sizeof(szo)          12             12      <- sizeof in the same position is FINE
```

So one `offsetof` anywhere in a static array initializer collapses the entire
declaration to a **single zero element**, and `sizeof` in the identical position
is correct — this is `offsetof`-specific, not a general constant-folding defect.

**Why that is worse than the filed summary, which says the value folds to zero.**
`sizeof(arr)/sizeof(arr[0])` — the standard idiom for a table's length — silently
becomes **1**. Every loop over such a table runs one iteration and stops. That is
the failure shape behind `uname -a` printing `Linux` eight times from a
pxx-built busybox: a table walk, not a value.

**A correction to this session's own first reading, because the trap is the
point.** Indexing `arr[0]`, `arr[1]`, `arr[2]` printed `0 4 0`, and I read that
as "offsetof is correct and the literals are zeroed" — a plausible mechanism,
confidently wrong. The array is one element long, so indices 1 and 2 were
**out-of-bounds reads** of whatever followed; the `4` was the neighbouring
`static int scal`. Nothing errored. `sizeof(ofs)` is what settled it, and it is
the only probe here that cannot be answered by adjacent memory. **Reading an
array whose length is the defect cannot measure that defect.**

Summary left as its author wrote it; it understates the mechanism and the
severity, and correcting it belongs to whoever holds the ticket.
