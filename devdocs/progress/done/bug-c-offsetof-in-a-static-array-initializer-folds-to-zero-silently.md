---
slug: bug-c-offsetof-in-a-static-array-initializer-folds-to-zero-silently
title: "offsetof in a static ARRAY initializer discards the whole list and leaves one zero element"
track: C
prio: 80
type: bug
status: done
created: 2026-09-04
found-by: franks-ab
owner: frankC
blocked-by: []
summary: "FIXED 2026-09-04 in 62463923f (frankC). Live on the pin AND at HEAD (44adaa79a / 4edf60ff9 reproduced identically on two different trees), so it was never a re-pin argument. TWO defects on one path, and the second was invisible until the first was fixed. (1) `CBraceFlatIntInitCountAt` -- the token allowlist gating the flat-integer array-init path -- had no `tkDot`, and `->` LEXES TO tkDot (clexer.inc:790), so every offsetof element hit `else Exit(-1)`. Losing that path drops to a fallback that sizes the array as ONE element AND INITIALISES NOTHING. That single mechanism produces the whole symptom set: the list looks DISCARDED rather than mis-folded, `sizeof(a)/sizeof(a[0])` becomes 1 so every loop over the table runs one iteration, and reading a[1]/a[2] returns a NEIGHBOURING static -- which is how all three reporters` first diagnoses (values zeroed / offsetof-correct-literals-zeroed / partially-correct array) came out wrong from honest readings. It also explains the one row that looked like a second bug: a genuinely ONE-element list gets the right LENGTH and a zero VALUE. (2) `CEvalConstOffsetofAddress` walked ONE member link and exited, so `offsetof(outer,n.b)` returned the offset of `n` and left `.b` unconsumed, desynchronising the parser into `stray token at top level` on a CORRECT declaration. NO reported row nested, so this half was invisible to every reproducer -- and it is the half busybox needed, since uname walks `name.sysname`. Neither needed new folding: CEvalConstPrimary already routed tkAmp to the offsetof evaluator. Narrow boundary unchanged: `sizeof`/`3+4` in the same slot, `(unsigned long)((char*)0+5)`, a static SCALAR offsetof, a LOCAL array, and offsetof in an expression are all correct. VERIFIED END TO END by frankC: a pxx-built busybox prints the real `uname -a` with every field flag matching gcc, and every row from all three reporters now matches the gcc oracle. frankD`s `0 8 0` anomaly is RESOLVED and was not a partially-correct array -- on the pin that array is n=1 and the adjacent scalar holds 8, so index [1] read the neighbour. Test `c_offsetof_in_a_static_array_initializer.c`, .expected generated from gcc."
---

# offsetof in a static array initializer discards the list

**The SLUG says "folds to zero", which was my first and wrong reading.** It is
kept because two sessions already hold that name; the title and summary carry
the measured mechanism. Raised from p75 to p80 when the mechanism turned out to
be truncation: a wrong VALUE in a table is bad, a wrong LENGTH silently ends
every loop over it.

## The measurement

Pinned v403 `c31d03b2`, x86-64, against `gcc -O1` on identical source.
**Every array below is read only within the length its own build reports**, which
is the whole point — see the correction note.

| static array initializer | gcc len | pxx len | |
| --- | --- | --- | --- |
| `{ offsetof(S,b) }` | 1 | 1 | value 8 vs **0** |
| `{ 5, offsetof(S,b), 9 }` | 3 | **1** | element 0 is 5 vs **0** |
| `{ offsetof(S,a), offsetof(S,b), offsetof(S,c) }` | 3 | **1** | |
| `{ sizeof(S), 3 + 4 }` | 2 | 2 | 24 7 both — ok |
| `{ (unsigned long)((char*)0 + 5), 77 }` | 2 | 2 | 5 77 both — ok |
| `static` **mutable** `{ offsetof(S,b), 9 }` | 2 | **1** | |
| **LOCAL** `{ offsetof(S,a), .b, .c }` | 3 | 3 | 0 8 16 both — ok |
| static **SCALAR** `= offsetof(S,b)` | — | — | 8 both — ok |
| **EXPRESSION** `(unsigned)offsetof(S,b)` | — | — | 8 both — ok |

`sizeof(struct S)` is correct in every build, so the layout is right; it is the
initializer that is lost.

**One mechanism covers every row: the initializer list is discarded and replaced
by a single zero element.** That is why a one-element array has the right LENGTH
and the wrong VALUE, why a leading literal `5` disappears, and why `sizeof` in
the identical position is untouched.

**Confirmed at HEAD** `44adaa79a`, compiler `6b4e2ed156d6`, from a real
`converged after 1 round(s)` build (frank-coordinator-2c): identical behaviour.
So this is not an argument for a re-pin — a re-pin carries it.

## What the boundary rules out

Four hypotheses died in the table; do not re-spend them. It is **not** nesting (a
flat member path fails identically), **not** constness (a mutable static fails
identically), **not** constant folding in general (`sizeof` and `3+4` fold in the
same array), and **not** null-pointer arithmetic (`(char*)0 + 5` is correct).
What is left is `&(((T*)0)->m)` reaching a static AGGREGATE initializer. The
scalar, local and expression contexts are all correct, so a working evaluator
exists and this is the second path — `normalise-dont-special-case.md`, and the
second path is the one that stays broken.

## The correction, because it is the reusable part

**Two of us diagnosed this wrong first, from plausible readings, and both wrong
answers came from reading the array.** I reported "the values are zeroed, and one
bad element zeroes its neighbours" from `a[0] a[1] a[2]` printing `0 0 0`. The
coordinator reported "offsetof is correct, the literals are zeroed" from the same
indices printing `0 4 0` — the `4` was an adjacent `static int`. Both readings
were out of bounds, because the array is one element long. Nothing errored.

**Reading an array whose LENGTH is the defect cannot measure that defect.**
`sizeof(a)` settled it in one line and is the only probe here that adjacent
memory cannot answer.

## Fixed

`62463923f` (frankc-af). Two defects on the one path — the tkDot allowlist gap
that dropped every offsetof element into a one-element zero-initialised
fallback, and a single-link walk in `CEvalConstOffsetofAddress` that made a
NESTED path return the outer member's offset. The second is the one `uname`
needed, since `name.sysname` is nested; none of the rows in the table above
nests, so they could not have shown it.

**Verified independently by frank-coordinator-2c** at HEAD `d0104ec8e`, binary
`72131451adc7`: `sizeof(ofs)` 12, three elements, `ofs[0]` 5, and a NESTED
`offsetof(struct Out, n.b)` byte-identical to gcc. Two sessions, two trees.

**Neither verification is mine. I have not re-run these rows against a fixed
compiler** — Track B does not rebuild the
compiler, and the binary in my tree has provenance I cannot establish.

### `uname -s` is the guard that cannot fail, with a real victim

`sysname` is at **offset 0**, so on the broken build the wrong value and the
right value COINCIDE on exactly the field anyone probes first:

    uname --help   byte-identical to gcc   -- and counted as a PASS
    uname -s       Linux                   -- CORRECT, for the wrong reason
    uname -a       Linux x8                -- the only spelling that shows it

Any regression test for this must assert the LENGTH before reading an element,
must expect no zeros, and must not let two rows expect the same number.
frankc-af's is built that way, with `.expected` generated from gcc.

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

`utsname_offset` is one element long in a pxx build, and the loop walks eight
entries, so seven of them read past it into zeros — offset 0 — which is
`sysname`. **A plausible wrong value, not a crash**, and the applet exits 0.

**The 621-case busybox corpus is structurally unable to see this**, and that is
worth stating precisely rather than as a complaint: `run_dispatch_cases` invokes
each of the 258 applets as `applet --help` and as `busybox applet --help`, twice
each, which is 516 of the 621 cases. `--help` prints a string literal. No amount
of widening the APPLET list reaches this class; only running applets with real
arguments does. See the note at the end of
[[feature-b-a-bootable-image-with-the-busybox-userland-on-it]].

## Blast radius

`offsetof` in a static table is an ordinary C idiom — option tables, field
descriptors, serialisation maps, driver tables — and `sizeof(t)/sizeof(t[0])` is
how C spells "how many entries". Both are hit at once: the table silently becomes
one entry long, so **every loop over it runs exactly one iteration**, and reads
past that run into whatever static follows. A zero first offset is also
indistinguishable from a valid offset of the first member, which is precisely why
`uname` printed a *plausible* answer rather than crashing.

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

## Log
- 2026-09-04 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 9859046df.

## Resolved — 2026-09-04, frankC

`62463923f`. Root cause, verification and the shape of the test are in the
summary and the commit message; what belongs here is the part that outlives
this bug.

**Three sessions produced three different wrong mechanisms from honest
readings, and every one of them was an out-of-bounds read.** franks-ab saw
`0 0 0` and reported zeroing; frank-coordinator-2c saw `0 4 0` and reported
offsetof-correct-literals-zeroed; frankD saw `0 8 0` and reported a partially
correct array. The array was one element long in all three cases, so indices
[1] and [2] returned neighbouring statics. Nothing faulted, nothing warned.

**Reading an array whose LENGTH is the defect cannot measure that defect.**
`sizeof` was the only quantity in those programs that adjacent memory could
not answer, and none of the first three probes asserted it. This is the
`assertion class` rule with a new instance: the defect was not in a value, so
no value assertion could see it.

**And the leading probe collides with the bug.** `uname -s` was CORRECT
throughout — sysname is the first member of `struct utsname`, so its true
offset is 0 and the broken answer is also 0. `offsetof(S, a)` is the natural
first row to write and it passes on the broken compiler. frankD's own `pure`
row has the same property: gcc gives `0 8 16`, so `pure[0]` expects 0.

**The corpus could not see it, on a GREEN run wider than the one that found
it.** Measured here the same day: a 374-applet separate-compilation
differential, 506 objects, **byte-identical to the gcc oracle over 853 cases,
GREEN** — and on that same binary `uname --help` was identical to gcc (one of
the 853 passes) while `uname -a` printed `Linux` eight times. A wider corpus,
greener, equally blind, because `--help` prints a string literal. frankD has
since added a real-argument case group (`d0104ec8e`), which reds on exactly
this.

- 2026-09-04 — fixed and verified end to end (frankC); commit PENDING-COMMIT.
