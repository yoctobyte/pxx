---
slug: task-b-nineteen-sysutils-names-that-fpc-keeps-in-system
track: B
type: task
prio: 45
status: done
found: 2026-09-06
found-by: frankS
owner: frankS
blocked-by: []
summary: "RESOLVED 2026-09-09: the classification the ticket asked for is done and six of the twelve are FIXED. A per-name no-uses probe (fpc 3.2.2 vs pxx, one program each, scratchpad ub/gen.py) ran ELEVEN of the twelve -- Error was not probed, it is also a compiler-internal name and needs sysutils' exception hierarchy -- and ALL ELEVEN were real: fpc runs them, pxx answered `undefined variable`. MOVED into compiler/builtin/builtin.pas with pre-scan triggers: AllocMem DynArraySize SetString sLineBreak UTF8Decode UTF8Encode, all six now matching fpc line for line in a no-uses PROGRAM and in a no-uses UNIT. HELD BACK, five: LowerCase StrLen StrPas SysBackTraceStr StringOfChar -- not on merit, on the PIN: lib/rtl builds with $(PXX_STABLE) against a FROZEN copy of compiler/builtin, so moving a name something in that build calls deletes it from the only place that build can look (measured twice: `make lib-test` failed every unit with `undefined variable (LowerCase)`, then again with StringOfChar). The split criterion is exactly \"does something built with $(PXX_STABLE) call it\", and the finishing trigger is a pin carrying the new unit-level pre-scan plus a refreshed frozen builtin -- carried forward as [[task-b-five-system-names-still-in-sysutils-are-waiting-on-a-pin-not-on-a-decision]]. CORRECTED 2026-09-09, same day: this summary claimed a SECOND hole at the unit level and there is none. A unit-level trigger was written and is now removed as dead code -- any `uses` clause already pulls `builtin`, and a unit is only ever compiled because a program `uses` it, so `builtin` is in scope before any unit is parsed. Measured by disabling each pull and rebuilding: without the unit-level BUILTIN pull the unit fixture still compiles and prints every row; without the unit-level MATH pull it is refused at `pi`. The math case is a real second hole because no `uses` clause pulls `math`; this one was not, and the lib-test failure that made me believe it was the FROZEN-BUILTIN problem below, misread. So this is NOT a third instance of [[bug-p-the-system-math-and-thread-surfaces-are-not-ambient-in-units]]. tarray13 advances from line 23 to line 67: DynArraySize is supplied, DynArrayIndex/DynArraySetLength still are not."
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

## Resolution, 2026-09-09 (frankS)

### What was measured, and it is the half the ticket refused to skip

The census named a POPULATION. A per-name probe turned it into a defect list:
one no-uses program per name, compiled against fpc 3.2.2 and against pxx, the
discriminator being `undefined variable` on our side. Eleven of the twelve ran;
**all eleven were real.**

```
name               fpc (no uses)   pxx, before      pxx, after
AllocMem           ok 0            undefined var    ok 0
DynArraySize       ok 5            undefined var    ok 5
SetString          ok abc          undefined var    ok abc
sLineBreak         ok 1            undefined var    ok 1
UTF8Decode         ok 3            undefined var    ok 3
UTF8Encode         ok abc          undefined var    ok abc
LowerCase          ok abc          undefined var    undefined var   (pin)
StrLen             ok 2            undefined var    undefined var   (pin)
StrPas             ok ab           undefined var    undefined var   (pin)
StringOfChar       ok xxxx         undefined var    undefined var   (pin)
SysBackTraceStr    ok 19           undefined var    undefined var   (pin)
Error              not probed      --               --              (deps)
```

`Error` is the twelfth and stays unprobed on purpose: it is a compiler-internal
name here as well, and FPC's `Error` is tied into the runtime error path, so it
needs sysutils' exception hierarchy before the question is even well posed.

### There were TWO holes, not one, and the second is a different scan

The program-level pre-scan in `pasparser_prog.inc` reads the **program's own
tokens**. Adding the six triggers there made a no-uses PROGRAM work and left a
no-uses UNIT still failing, because the unit's tokens are never in that scan.
`pasparser_proc.inc` needed its own `unitNeedsBuiltinSys` clause. That is the
**third instance** of the same shape — the math/thread surface was the first,
the Classes enumerators the second — so the class is about the SCAN being
per-file, not about any of the three name sets.

### The five that stayed, and why it is not a ranking

`lib/rtl` is built with the **pinned** compiler against a **frozen** copy of
`compiler/builtin/` — `make lib-test` prints exactly that on its second line,
*"isolates track A's compiler/builtin/ edits"*. So a name MOVED out of
`lib/rtl/sysutils.pas` is gone from the only place that build can resolve it.
With all eleven moved, `make lib-test` failed **every** unit with `undefined
variable (LowerCase)`, raised from inside sysutils.pas itself.

The consumer grep that produced the first four covered `lib/` and `examples/`
and **not** the `test/lib_` rows, which are lib-test rows built the same way —
so StringOfChar cost a second identical failure at `lib_strpchar.pas:49`. **The
population for this question is everything the pinned build compiles**, not
everything under `lib/`.

### Inert until pinned — say it here rather than wait for it

The six moved names work at HEAD and are invisible to anything building with
`$(PXX_STABLE)` until the next pin carries them. Nothing in `lib/**` depends on
that, because the moved six are exactly the ones nothing in that build calls —
which is the same criterion, read the other way round.

### Landed

- `compiler/builtin/builtin.pas` — six declarations and bodies, with the class
  note and the finishing trigger.
- `compiler/pasparser_prog.inc` — program-level triggers (call-shaped group, plus
  `slinebreak` in the bare-name group).
- `compiler/pasparser_proc.inc` — `unitNeedsBuiltinSys`, the unit-level scan and
  the `ParseUsesUnitAmbient('builtin')` pull.
- `lib/rtl/sysutils.pas` — six declarations and bodies removed, each replaced by
  a MOVED note; StringOfChar kept with its own note.
- `test/test_b_system_names_reach_a_program_with_no_uses_clause.pas` — the
  program half, 8 rows, fpc's output verbatim.
- `test/units/uambientsys.pas` + `test/test_unit_ambient_system_surface.pas` —
  rows d..h, the unit half. The program names none of the six, which is what
  makes those rows fail if the unit-level pull is ever dropped.

## Log
- 2026-09-09 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 0ffe185bb.

## CORRECTION, 2026-09-09, hours after the resolution above (frankS)

**The "two holes, two scans" half of this resolution was wrong and is retracted.
The six names, the probe, the eleven-of-twelve classification and the pin-shaped
split are unaffected.**

I added a unit-level trigger (`unitNeedsBuiltinSys`, `pasparser_proc.inc`)
believing a no-uses UNIT could not otherwise reach the moved names. It is dead
code and has been removed.

### The control I did not run, and what it says

Disable one pull, rebuild, run `test_unit_ambient_system_surface`:

| pull disabled | result |
| --- | --- |
| unit-level **builtin** | compiles, every row prints — **the clause could never fail** |
| unit-level **math** | refused at `pi` — that clause is load-bearing |

**Any `uses` clause pulls `builtin`** (the tkUses arm, which my own comment in
`builtin.pas` already said), and a unit is only ever compiled because a program
`uses` it — pxx refuses a standalone unit outright. So `builtin` is in scope
before any unit is parsed. `math` is different: nothing pulls it for you, which
is why the earlier fix needed a unit-level clause and this one did not.

Confirmed independently with a name that has **no trigger in either scan**:
`VariantTagName`, declared in `builtin.pas`, is refused from a no-uses PROGRAM
and compiles fine from a no-uses UNIT.

### Why I believed it — AND THIS TICKET'S TWO FINDINGS WERE ONE OBSERVATION

Read top to bottom this ticket looks like it found two independent things: a
unit-level ambient hole and a frozen-builtin split. **They are one observation,
read twice.** `make lib-test` failed every unit with `undefined variable
(LowerCase)` while only the program-level trigger existed. That single failure
is the entire evidence for both readings, and only the second one is true — the
pinned build cannot see a name moved out of `lib/rtl`.

**The error string is doing the work a discriminator should do.** `undefined
variable (X)` is what a missing ambient pull says and what a name missing from
the frozen builtin says, so the message cannot separate them and I picked the
hypothesis already in hand. The fixture I then wrote to prove the unit-level
reading passes with or without the clause, so it could not separate them either
— it certified the belief instead of testing it.

The discriminator, when it was finally run, is not a better error message but a
**differential build**: disable one pull, rebuild, see which fixture moves.

### What is left of the class claim

Two instances, not three: the math/thread surface and the Classes enumerators.
The shape is still "an ambient unit that nothing pulls for you", and the six
names never had it — `builtin` is pulled by every `uses` clause there is.

frank-coordinator's probe is what started this: it found `UniqueString` and
`RunError` reaching a no-uses unit while sitting in the program scan only, and
said plainly that it had NOT established they were the same mechanism. They
were not, and the question it flagged is the one that turned out to matter.
