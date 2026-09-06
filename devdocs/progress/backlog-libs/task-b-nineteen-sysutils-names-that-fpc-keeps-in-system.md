---
slug: task-b-nineteen-sysutils-names-that-fpc-keeps-in-system
track: B
type: task
prio: 45
status: backlog
found: 2026-09-06
found-by: frankS
owner: ""
blocked-by: []
summary: "TWELVE names an FPC program uses with NO uses clause and a pxx program cannot: AllocMem DynArraySize Error LowerCase SetString sLineBreak StringOfChar StrLen StrPas SysBackTraceStr UTF8Decode UTF8Encode. They are the second sign of the unit-boundary class whose first sign frankD fixed at f5ad23c32 (a sysutils declaration SHADOWING dyn-array Delete/Insert; declarations removed by frankH at 475528dae) -- opposite directions, same root, same tell of one `uses` line changing the answer. Measured TWICE with probes that fail differently, agreeing name for name: 167 sysutils interface routines, 17 that fpc resolves ambiently, 5 of those ambiently reachable here too (Concat/Copy/Pos/UpCase parser intrinsics, HexStr a builtin export), 12 left. Reproduce with tools/rtl_unit_boundary_census.py. THIS IS A POPULATION TO CHECK, NOT TWELVE CONFIRMED BUGS -- only DynArraySize is shown to break a real program (frankS: tarray13 dies at line 23, one `uses sysutils` advances it to line 68). sLineBreak is a const not a routine, and Error is also a compiler-internal name; both need a look before being treated as RTL gaps."
---

# Twelve names sit on the wrong side of our unit boundary — the second sign of a class whose first sign is fixed

## The class has two signs and they point opposite ways

Two seats hit it within an hour, from opposite directions, and **neither
instance names the other**:

| sign | what the declaration does | measured | fix direction |
| --- | --- | --- | --- |
| **shadow** | takes away a capability we already have | frankD, `f5ad23c32` — `uses sysutils` closed dynamic-array `Delete`/`Insert` for essentially every program in the tree | **remove** the declaration (done, frankH, `475528dae`) |
| **only home** | is the sole place the capability exists | frankS, today — `DynArraySize` at `lib/rtl/sysutils.pas:733`/`:5695`; tarray13 fails at line 23 with `undefined variable (DynArraySize)`, and one `uses sysutils` line advances it to line 68 | **add** the name to the implicit surface |

Same root — the unit boundary is drawn in the wrong place — and **the same tell,
one `uses` line changing the answer.** frankS's warning is why this row exists:
*"a fix that only handles the shadowing sign will read as complete."* It nearly
did: the shadow direction is now closed for sysutils with a control (frankH
intersected the 15 `SoftIntrinsicOpen` names with sysutils' declarations —
`['Delete', 'Insert']` at HEAD, `[]` after the commit, **same script both trees,
so a `[]` meaning "my regex broke" would have shown as `[]` on both**), and
nothing in that result mentions the other twelve.

## The twelve

```
AllocMem   DynArraySize   Error       LowerCase
SetString  StrLen         StrPas      StringOfChar
SysBackTraceStr   UTF8Decode   UTF8Encode   sLineBreak
```

**Reachable here after all, so NOT gaps:** `Concat`, `Copy`, `Pos`, `UpCase`
(parser intrinsics) and `HexStr` (ambient unit export). `Copy`, `UpCase` and
`Pos` were independently measured clear by frankD while narrowing the shadow.

## The predicate, published — both halves are required

`tools/rtl_unit_boundary_census.py` reproduces this. 167 routines in our
sysutils **interface** → 17 fpc resolves ambiently → 5 of those are ambiently
reachable here too → **12**.

**Half one, the fpc side. The oracle is fpc itself, not a grep of its sources.**
Compile a one-statement program with no uses clause and read one discriminator:
whether fpc says `Identifier not found`. Any other outcome — wrong parameter
count, a type error, success — means the name RESOLVED. Grepping `systemh.inc`
answers what one header spells and misses everything reaching `system` through
the include chain or through objpas. **Note what this is complete about:** it is
*"an fpc program does not need `uses sysutils` for this"*, which is the question
we care about, and it is **not** literally *"the name is in `system`"* — objpas
counts too.

**Half two, the pxx side, and it is what takes 17 to 12.** Of the fpc-ambient
names, which can a pxx program use with no uses clause: a parser intrinsic
(`CaseEqual(name, 'X')` across the four `pasparser_*.inc`) or a routine an
ambient unit's interface exports (`compiler/builtin/builtin.pas`,
`builtinheap.pas`).

**Controls, all branched on — the census exits 3 rather than printing a result.**
The fpc-side controls are probed DIRECTLY rather than looked for in the output,
which matters: the first version required `Delete` and `Insert` to appear among
our declarations, and `475528dae` removed both hours later, so it exited 3 on a
tree where nothing was wrong. **A control that encodes a defect stops being a
control the moment the defect is fixed.** Now: `Delete`/`Insert`/`DynArraySize`
must resolve under fpc and `Format`/`IntToStr`/`UpperCase`/`ChangeFileExt` must
not; a nonsense identifier must come back not-found on both sides, or every
answer either side gives is "yes"; `Copy`/`Pos`/`UpCase` must come back
reachable HERE; not every candidate may come back reachable; and `DynArraySize`
must survive into the gap list.

**Those pxx-side controls earned themselves, and the story is the reason they
are there (frankH):** two earlier probe shapes — `if @Length = nil then ;` and a
bare `Length;` — each reported **all 17 of 17** absent, because neither shape is
how pxx resolves an intrinsic. *"A census reporting ALL of its candidates is the
tell"*, and without `Copy`/`Pos`/`UpCase` as must-find rows the list would have
been seventeen names that were really *"my probe cannot see intrinsics"*.

## Two independent measurements, and they are genuinely two

frankH and this seat measured the fpc side with **different probe shapes**
(`if @X = nil then ;` under `-Mobjfpc -Sh`, versus a bare `X;` statement under
both `{$mode fpc}` and `{$mode objfpc}`) on **different trees** (before and after
`475528dae`), and got the same 17/5/12 split, **name for name**. Those two can
fail differently — an address-of probe is defeated by anything whose address
cannot be taken, a statement probe by anything that is not a statement — so the
agreement is corroboration rather than one method run twice.

## What is NOT established, and it is the larger half

**Nobody has shown that any of the other eleven breaks a real program.** Only
`DynArraySize` has a vehicle (tarray13). The rest is the reachability question,
which is exactly the half that got the ESP fork wrong this morning by never
being asked. Two rows need a look before they are treated as RTL gaps at all:

- **`sLineBreak` is a const in FPC's system, not a routine** — ours is a
  function at `lib/rtl/sysutils.pas:501`/`:1143`, and the comment at `:498`
  already says *"System.DynArraySize"*'s counterpart in so many words. It
  belongs on the list on the merits and not as a "routine".
- **`Error` is also a compiler-internal name here.**

The other ten look clean.

## Where the other side is

**There is no `lib/rtl/system.pas` in this tree.** The implicit surface is
`compiler/builtin/builtin.pas` + `builtinheap.pas`, which already exports at
least one fpc-facing **unprefixed** name — `GetFPCHeapStatus` — so the precedent
for putting a `system` name there exists rather than needing to be invented
(frankS). `EspBareBoot` is the only profile that excludes the builtin unit
(`ParseUsesUnitAmbient('builtinheap')` in `pasparser_prog.inc`), and on it `uses
sysutils` does not compile at all, so the ESP trade-off the decide row carried
was void in both ESP profiles (frankH).

## Provenance, per item

The shadow sign, `f5ad23c32`, and the `Copy`/`UpCase`/`Pos` clearance are
frankD's. `DynArraySize`'s two sites, tarray13's line 23 → line 68, the
two-signs reading and the `GetFPCHeapStatus` precedent are frankS's, measured on
tarray13 today. The removal `475528dae`, the shadow-direction completeness
control, the pxx-side half of the predicate and its three must-find rows, and
the `sLineBreak`/`Error` caveats are frankH's. The committed census, its fpc-side
oracle and the independent confirmation of the 17/5/12 split are this seat's, run
at HEAD on fpc 3.2.2. **The classification of the twelve is nobody's yet.**
