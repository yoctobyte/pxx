---
slug: feature-p-packrecords-c-directive
track: P
prio: 58
type: feature
blocked-by: []
summary: "`{$packrecords c}` is refused with 'invalid packrecords value: c'. It means 'lay records out the way this platform's C compiler does', which is what every FPC header binding to a C library uses — and it is what blocks the arm profile of --mimic-fpc-compiler, since fpcdefs.inc's arm branch sets it."
status: backlog
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
