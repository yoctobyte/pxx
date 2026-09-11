---
slug: feature-b-rtl-has-no-tdoublerec
title: "`lib/rtl` declares no `TDoubleRec`, and it is the FPC-compiler march's cfileutl wall"
track: B
prio: 40
type: feature
status: open
owner: ""
found-by: frankH
created: 2026-09-11
tags: [rtl, floats, fpc-corpus, sysutils]
blocked-by: []
summary: "`grep -rn TDoubleRec lib/rtl/ compiler/builtin/` is empty. FPC's `x86_64/cpuinfo.pas:36` writes `bestrealrec = TDoubleRec`, so the FPC-compiler-source march stops there with `unknown type: TDoubleRec` -- the wall cfileutl reached once `TExecuteFlags` was cleared. fpc declares it in `rtl/inc/mathh.inc:172` as a packed record overlaying a Double, with PRIVATE const `Bias = $3FF` and property-backed `GetExp/SetExp/GetSign/SetSign/GetFrac/SetFrac`. cfileutl only needs the TYPE to exist for an alias; nothing in the march has yet asked for the accessors, so the cheap version is the layout and the expensive one is the property surface -- measure which is needed before building the second."
---

# The wall

```
pascal26:36: error: unknown type: TDoubleRec
  in: /home/neo/src/fpc-trunk/compiler/x86_64/cpuinfo.pas
  near: bestreal = extended ; bestrealrec = >>> TDoubleRec ; ts32real
```

Reached 2026-09-11 by [[feature-b-sysutils-has-no-executeprocess-and-no-texecuteflags]]
clearing `cfileutl.pas:136 unknown type: TExecuteFlags`. One unit of FPC's 207
stops here today.

**Do not rank this on unit count.** The umbrella's standing finding is that a
wall's population is a queue position, not a size, and the wall this one
replaced was three units that were all the same LINE of the same file.

## What fpc has

`rtl/inc/mathh.inc:172`, guarded by `{$ifdef SUPPORT_DOUBLE}`: a packed record
over a Double with a private `Bias = $3FF` and six private accessors behind
public properties for sign / exponent / fraction.

The sibling types (`TSingleRec`, `TExtended80Rec`) live beside it and are
equally absent; check whether the march wants them before adding only one.
