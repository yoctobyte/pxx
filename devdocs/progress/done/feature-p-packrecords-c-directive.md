---
slug: feature-p-packrecords-c-directive
track: P
prio: 58
type: feature
blocked-by: []
summary: "`{$packrecords c}` is refused with 'invalid packrecords value: c'. It means 'lay records out the way this platform's C compiler does', which is what every FPC header binding to a C library uses — and it is what blocks the arm profile of --mimic-fpc-compiler, since fpcdefs.inc's arm branch sets it."
status: done
owner: frankS
---

# `{$packrecords c}` is refused

Found 2026-08-21 while adding the arm arm of
[[feature-mimic-fpc-compiler-define-profile]]:

```
$ pascal26 --target=arm32 --mimic-fpc-compiler p.pas
pascal26:1: error: invalid packrecords value: c
```

FPC 3.2.2's `fpcdefs.inc` opens its arm branch with `{$packrecords c}`, so the
arm profile cannot get past the include even though the define derivation
itself is correct.

## What it means

`{$packrecords N}` sets record field alignment to N bytes. `c` is not a number:
it means **"use the alignment rules this platform's C compiler uses"** — which
is not always the same as any single N, because C's rule is per-field natural
alignment capped by the ABI. It is the directive every FPC binding to a C
library uses, so this is not arm-specific or FPC-compiler-specific surface.

## Scope, and the honest version of it

pxx's record layout for `extern "C"` interop already has to answer this
question — `lib/crtl` and the C frontend share the IR's record layout — so the
rule likely exists and the gap is the directive spelling. Confirm that before
scoping: if pxx's default record layout already IS C-compatible on the hosted
targets, `{$packrecords c}` is close to a no-op there and the fix is accepting
the value rather than implementing a mode. If it is not, accepting the
directive silently would be a **silent wrong layout**, which is worse than the
current refusal — in that case it stays refused until the mode exists.

That fork is why this is filed rather than fixed: the cheap version and the
correct version are the same edit only if the premise holds.

## Gate

`{$packrecords c}` accepted with the layout it promises (verified against a gcc
oracle on a struct with mixed field widths, which `tools/gcc_diff_probe.sh`
already does), and the arm arm of `--mimic-fpc-compiler` reaching past
`{$i fpcdefs.inc}`.

## Fixed 2026-09-04 (frankS, Track P)

**The premise held, and it was measured rather than assumed** — which is what
this ticket said to check before scoping, since the cheap fix and the correct
fix are the same edit only if it does.

`PackRecordsVal` is read in exactly one place (`pasparser_decl.inc`:
`if fAlign > TokPackRecords[TokPos-1] then fAlign := TokPackRecords[TokPos-1]`),
as a CEILING on a field alignment that is already `TypeFieldAlign` — and
`TypeFieldAlign` IS the platform C rule, i386's 4-byte cap on an 8-byte scalar
included, itself measured against gcc when
`bug-a-an-8-byte-scalar-is-over-aligned-inside-a-struct-on-i386` was fixed.
`TypeAlign` never answers above 8.

So **`c` is a NO-CAP, not a mode**: it means "do not cap, the rule underneath is
already C's". Implemented as `PackRecordsVal := 16`, not as a synonym for the
default 8 — identical today, and still correct the day a 16-aligned type
appears, where the synonym would silently be wrong.

**Verified against gcc on both targets, offsets and sizeof, not just sizeof**
(`test-packrecords-c-gcc-oracle`, `struct { char a; double b; short c; int d;
char e; }`):

```
             gcc            pxx {$packrecords c}
  x86-64     0 8 16 20 24 32   0 8 16 20 24 32
  i386       0 4 12 16 20 24   0 4 12 16 20 24
```

The two target rows must differ from each other as well as match their oracle,
so a run that measured the wrong target mismatches instead of passing quietly.

**The `{$packrecords 1}` row in the same file is the positive control and it is
the whole test.** pxx's DEFAULT layout already agrees with gcc, so line 1 would
match even if `{$packrecords c}` were accepted and discarded — which is exactly
how the rest of this directive family used to fail. Only a row whose answer must
differ (`0 1 9 11 15 16`) separates "the directive worked" from "the directive
was thrown away". Negative-controlled: pointing both rows at `c` makes the gate
go RED with that reason, not green.

**Second gate condition met.** `pascal26 --target=arm32 --mimic-fpc-compiler`
now gets past `{$i fpcdefs.inc}` (FPC 3.2.2's, line 48 is the `{$packrecords c}`
that blocked it). The include now reports two further gaps that were silent
before — `{$H-}` and `{$PACKENUM 1}`, both in fpcdefs.inc's first nine lines —
filed as `feature-p-packenum-and-h-minus-for-the-fpc-compiler-corpus`. Those are
the arm profile's NEXT wall, not this one.

## Log
- 2026-09-04 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit b4017f96d.
