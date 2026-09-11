---
slug: feature-b-rtl-has-no-tdoublerec
title: "`TDoubleRec` is declared nowhere pxx can see, and fpc has it in System"
track: P
prio: 25
type: feature
status: open
owner: ""
found-by: frankH
created: 2026-09-11
tags: [rtl, floats, fpc-corpus, type-visibility]
blocked-by: [bug-p-a-unit-cycle-closed-through-an-implementation-uses-cannot-see-the-other-interface]
summary: "RE-LANED AND RE-PRICED 2026-09-11, HOURS AFTER FILING, BY ITS OWN AUTHOR -- the slug still says `rtl-has-no`, kept so citations resolve, and BOTH halves of the original framing were wrong. (1) NOT TRACK B: fpc declares `TDoubleRec` in `rtl/inc/mathh.inc`, which `systemh.inc` INCLUDES, so it is in the System unit and always in scope -- `x86_64/cpuinfo.pas:36` writes `bestrealrec = TDoubleRec` while its interface uses only `globtype`. Adding a record to a `lib/rtl` unit therefore cannot fix it; a type in `compiler/builtin/builtin.pas` is not globally visible either (measured: `var r: TVariantRecord` in a bare program answers `unknown type`). This is compiler-side type-name visibility, Track P/A. (2) IT BUYS ZERO UNITS TODAY, PROVED not predicted: cfileutl -- the only unit that reaches this wall -- has `implementation uses Comphook, Globals`, and `globals` alone already fails at `comphook.pas:251 undefined variable (V_Status)`. So cfileutl cannot compile whatever happens here. Dropped 40 -> 25 and blocked-by the unit cycle."
---

# The wall

```
pascal26:36: error: unknown type: TDoubleRec
  in: /home/neo/src/fpc-trunk/compiler/x86_64/cpuinfo.pas
  near: bestreal = extended ; bestrealrec = >>> TDoubleRec ; ts32real
```

Reached 2026-09-11 by [[feature-b-sysutils-has-no-executeprocess-and-no-texecuteflags]]
clearing `cfileutl.pas:136 unknown type: TExecuteFlags`.

## Why this was re-laned within hours of being filed

It was filed on the strength of `grep -rn TDoubleRec lib/rtl/ compiler/builtin/`
coming back empty, which is true and which does not locate the fix. Two things
had to be checked and were not:

- **Where fpc puts it.** `rtl/inc/mathh.inc`, included by `systemh.inc` — the
  System unit, in scope everywhere without a `uses`. `cpuinfo.pas`'s interface
  uses only `globtype`, which is the proof: nothing it names could supply the
  type.
- **Whether pxx has an equivalent shelf.** `compiler/builtin/builtin.pas` is
  auto-included for specific constructs, not globally scoped. Measured: a bare
  program declaring `var r: TVariantRecord` — a type that unit does declare at
  :1123 — answers `unknown type: TVariantRecord`.

So the fix is a compiler-side type the frontend knows, not an RTL declaration,
and the lane is P/A rather than B.

## And it buys nothing until the unit cycle is fixed

**The expectation was written before looking and it held.** cfileutl is the
only unit standing at this wall, and its implementation section reads:

```pascal
implementation
    uses
      Comphook,
      Globals;
```

`globals` on its own already fails —
`comphook.pas:251 undefined variable (V_Status)`, where `V_Status` is declared
inside the corpus at `globals.pas:149` — so cfileutl is behind
[[bug-p-a-unit-cycle-closed-through-an-implementation-uses-cannot-see-the-other-interface]]
(p60, 158 units) no matter what happens to `TDoubleRec`. That is why this is
`blocked-by` it and priced at 25.

This did not need a build to settle: `globals` failing alone plus cfileutl
depending on `globals` is a proof, not a prediction.

## Shape, when it is worth doing

fpc's is a packed record over a Double with a private `Bias = $3FF` and six
private accessors behind public sign / exponent / fraction properties. The
siblings `TSingleRec` and `TExtended80Rec` sit beside it and are equally
absent — `cpuinfo.pas:34` takes the `TExtended80Rec` arm under
`FPC_HAS_TYPE_EXTENDED`, so check which arm our define profile selects before
building only one.
