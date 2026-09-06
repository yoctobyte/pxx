---
slug: task-b-nineteen-sysutils-names-that-fpc-keeps-in-system
track: B
type: task
prio: 45
status: backlog
found: 2026-09-06
found-by: frank-coordinator
owner: ""
blocked-by: []
summary: "`lib/rtl/sysutils.pas` declares NINETEEN names that FPC resolves with no uses clause at all -- measured by asking fpc, not by grepping it (`tools/rtl_unit_boundary_census.py`, 169 interface routines probed, controls branched on): AllocMem Concat Copy Delete DynArraySize Error HexStr Insert LowerCase Pos SetString sLineBreak StringOfChar StrLen StrPas SysBackTraceStr UpCase UTF8Decode UTF8Encode. The class has TWO SIGNS pointing opposite ways -- the declaration SHADOWS a capability we already have (frankD: `uses sysutils` took dyn-array Delete/Insert from every program, fixed f5ad23c32) or it is the ONLY home of one (frankS: tarray13 dies at line 23 on `undefined variable (DynArraySize)`, one `uses sysutils` line advances it to line 68). Six rows are already classified: Delete/Insert were sign one, DynArraySize is sign two, Copy/UpCase/Pos measured CLEAR by frankD. Thirteen are unclassified and the census cannot say which sign a row has -- that is the work. A fix that handles only the shadowing sign will read as complete."
---

# Nineteen names sit on the wrong side of our unit boundary, and the class has two signs

## Why this is one ticket and not nineteen

Two seats hit this defect within an hour of each other, **from opposite
directions**, and neither instance names the other:

| sign | what the declaration does | measured | fix direction |
| --- | --- | --- | --- |
| **shadow** | takes away a capability we already have | frankD, `f5ad23c32` — `uses sysutils` closed dynamic-array `Delete`/`Insert` for essentially every program in the tree | **remove** the declaration |
| **only home** | is the sole place the capability exists | frankS, today — `DynArraySize` at `lib/rtl/sysutils.pas:733`/`:5695`; tarray13 fails at line 23 with `undefined variable (DynArraySize)`, one `uses sysutils` line advances it to line 68 | **add** the name to the implicit surface |

Same root — the unit boundary is drawn in the wrong place — and **the same tell,
one `uses` line changing the answer.** frankS's point is the reason this exists
as a row: *"a census that greps sysutils for names fpc keeps in `system` finds
both, and a fix that only handles the shadowing sign will read as complete."*

## The census, and what it is complete about

`tools/rtl_unit_boundary_census.py`. 169 routine names in our sysutils
**interface**; 19 of them resolve under FPC with **no uses clause**.

**The oracle is fpc itself, not a grep of fpc's sources.** For each name, compile
a one-statement program with no uses clause and read one discriminator: whether
fpc says `Identifier not found`. Any other outcome — wrong parameter count, a
type error, success — means the name RESOLVED. Grepping `systemh.inc` answers a
different question (what one header spells) and misses everything reaching
`system` through the include chain or through objpas. Both `{$mode fpc}` and
`{$mode objfpc}` are probed; a row visible in only one is marked.

Controls, all branched on, the census exits 3 rather than printing a result if
any fails: `Delete`, `Insert` and `DynArraySize` must appear (three names two
seats measured today); `Format`, `IntToStr`, `UpperCase`, `ChangeFileExt` must
not (sysutils' in fpc too — a census that flags them flags everything); a
nonsense identifier must come back not-found, or every answer it gives would be
"in system"; and discovery must find at least 100 interface routines.

**What it is NOT complete about, and this is the whole residual:** it names
where the doors are, not what shape reaches each one. It cannot tell a shadow
from an only-home, and it cannot tell either from a row that is simply fine.

## The nineteen

```
AllocMem  Concat  Copy  Delete  DynArraySize  Error  HexStr  Insert  LowerCase
Pos  SetString  sLineBreak  StringOfChar  StrLen  StrPas  SysBackTraceStr
UpCase  UTF8Decode  UTF8Encode
```

**Six are already classified and must not be re-measured:**

- `Delete`, `Insert` — sign one, the defect, fixed at `f5ad23c32`. The
  declarations themselves are still there; removal is owned by frankH under
  `decide-where-the-string-delete-and-insert-routines-should-live` (resolved:
  frankH measured the ESP cost at HEAD and there was no fork — on the bare ESP
  profile `uses sysutils` does not compile at all).
- `DynArraySize` — sign two. Note `lib/rtl/sysutils.pas:728` already says
  *"System.DynArraySize"* in a comment: the author knew where FPC keeps it.
- `Copy`, `UpCase`, `Pos` — **measured CLEAR by frankD** while narrowing the
  Delete/Insert shadow. Do not re-open them off this list.

**Thirteen are unclassified**, and each needs one question asked of it — is this
a shadow, an only-home, or fine:

```
AllocMem  Concat  Error  HexStr  LowerCase  SetString  sLineBreak
StringOfChar  StrLen  StrPas  SysBackTraceStr  UTF8Decode  UTF8Encode
```

`sLineBreak` is a third variant worth naming: FPC has it as a **const in
system**, ours is a **function in sysutils** (`:501`, `:1143`), and the comment
at `:498` says so.

## Where the other side is

**There is no `lib/rtl/system.pas` in this tree.** The implicit surface is
`compiler/builtin/builtin.pas` + `builtinheap.pas`, which already exports at
least one fpc-facing **unprefixed** name — `GetFPCHeapStatus` — so the precedent
for putting a `system` name there exists rather than needing to be invented
(frankS).

## Provenance, per item

The shadow sign, `f5ad23c32`, and the Copy/UpCase/Pos clearance are frankD's,
measured. `DynArraySize`'s two sites, tarray13's line 23 → line 68, the
two-signs reading and the `GetFPCHeapStatus` precedent are frankS's, measured on
tarray13 today. The nineteen names, the oracle and its controls are this seat's,
run at HEAD on fpc 3.2.2. The classification of the thirteen is nobody's yet.
