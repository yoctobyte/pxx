---
slug: bug-p-an-array-constant-with-a-set-element-type-cannot-be-initialised
title: "An array constant whose ELEMENT type is a set cannot be initialised at all"
track: P
prio: 80
type: bug
status: open
owner: ""
found-by: frankuser
created: 2026-09-16
tags: [pascal, sets, array-constants, fpc-corpus, sibling-of-a-fixed-arm]
blocked-by: []
summary: "`var a: array[0..0] of set of TF = ([]);` is refused with `too many array initializer elements` — a SINGLE empty set against a one-element bound, so the message is misleading and the defect is not a count. Measured 2026-09-16: the enum-indexed half is fine (`array[TC] of Integer` compiles), the SET ELEMENT TYPE is the whole cause. This is the UNFIXED SIBLING of bug-p-a-set-valued-record-field-cannot-be-written-in-a-record-constant, which 138604b5e fixed for the record arm — the record arm compiles today, the array arm never did. Gates x86_64/cpuinfo.pas:281 (`cpu_capabilities: array[tcputype] of set of tcpuflags`, whose 23 initializer elements exactly match tcputype's 23 members, so FPC's source is correct). Together with feature-b-rtl-has-no-tdoublerec it is one of EXACTLY TWO errors reported by 132 of FPC's 207 units — see umbrella-pxx-compiles-fpc-itself."
---

# An array constant with a set element type cannot be initialised

- **Umbrella:** `umbrella-pxx-compiles-fpc-itself`
- **Sibling, already fixed:** [[bug-p-a-set-valued-record-field-cannot-be-written-in-a-record-constant]]

## Repro, 4 lines

```pascal
program p;
type TF = (fa, fb, fc);
var a: array[0..0] of set of TF = ([]);
begin WriteLn(1); end.
```

```
pascal26:3: error: too many array initializer elements
  near: of set of TF = ( >>> [ ] ,
```

**One element, one slot, and it still says "too many".** The diagnostic names a
count and the defect is not a count — widening the bound does not help:
`array[0..5] of set of TF = ([],[fa],[fa,fb])` fails identically. The `[` that
opens a set literal is being read as the start of a nested initializer.

## What is NOT the cause — measured, not assumed

| probe | result |
| --- | --- |
| `array[TC] of Integer = (10,20,30)` — enum bound, scalar element | **compiles**, prints 30 |
| `array[0..2] of set of TF = ([],[fa],[fa,fb])` — integer bound, set element | **refused** |
| `const r: TR = (s: [fa,fb]; n: 7)` — set in a RECORD constant | **compiles** |

So the enum index is innocent and so is the set type itself. It is specifically
**a set as an ARRAY CONSTANT's element**.

## Why it matters now

`x86_64/cpuinfo.pas:281`:

```pascal
cpu_capabilities : array[tcputype] of set of tcpuflags = (
  { cpu_none } [],
  { Athlon64 } cpu_x86_64_v1_flags, ... );
```

`tcputype` has **23** members and the initializer has **23** elements — FPC's
source is correct and we are wrong about it.

**132 of FPC's 207 compiler units report EXACTLY TWO errors and these are they**:
`unknown type: TDoubleRec` (cpuinfo.pas:36) and this one (cpuinfo.pas:281).
Nothing else, and the 20-error recovery cap is not in play — only one unit in the
whole corpus reaches it. **Both walls are in ONE FILE.**

**Do not read 132 as this ticket's yield.** A wall's population counts units
QUEUED behind it, not work (CLAUDE.md), and this umbrella has measured five
straight conversions at 0, 3 and 2 units. What IS new here is that these two are
the units' *complete* reported failure set rather than their first — so clearing
BOTH is the first proposal this umbrella has had with evidence behind it rather
than a queue position. A third wall in the same file is still the most likely
outcome and should be expected, not treated as a surprise.

## Where to start

`138604b5e` fixed the record arm. Read what it did and look for the array arm
beside it — `normalise-dont-special-case.md`: fixed one arm of a double case,
grep for the sibling before closing. That is exactly what happened here, and
this ticket exists because nobody did.
