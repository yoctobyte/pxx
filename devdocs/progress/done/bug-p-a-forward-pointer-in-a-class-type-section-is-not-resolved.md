---
track: P
prio: 45
type: bug
blocked-by: []
status: done
owner: frankZ
found-by: frankS
created: 2026-09-09
summary: "FIXED 2026-09-09. A forward `^T` inside a CLASS's or RECORD's nested `type` section was not resolved when T is a nested plain ALIAS, POINTER alias or SUBRANGE -- and WAS resolved when T is a nested CLASS, RECORD, ARRAY or ENUM. THE TICKET'S FRAMING WAS ONE STEP TOO NARROW: it reads as a pointer-to-pointer defect and the chain depth is irrelevant; the discriminator is the KIND of the forward target, and five-of-eight passing is a per-TABLE shape. Cause: DrainPendingPtrTargets asked FindNestedType (class-like only) and then the FLAT FindTypeAlias -- which filters through AliasVisibleHere and therefore reads ParsingClassBodyCi -- and the drain runs at the unit's closing `end.` where that is -1. So FindTypeAlias correctly reported a nested alias as not visible FROM HERE; every arm was working and none was asking the row's question. The three kinds that passed did so only because IsRecordType / FindArrayType / FindEnumType carry no owner column and are asked UNSCOPED. Fixed by asking ClassDeclaresTypeNamed, which is exactly this question, consults FindNestedType first (so nothing that resolved can stop resolving) and walks the ancestor chain, which these arms did not. CLEARS THE REGRESSION IT WAS FILED BEHIND -- and that regression was never one: frankH measured pin v407 failing at :224 on identical input, so ad7c03b03 did not cause it, it REMOVED an earlier wall so the end-of-unit drain could finally speak about a declaration 2500 lines back. 224 < 2729 reads as backward only because one is a stopping point and the other a declaration site. generics.defaults.pas now compiles and the driver runs -- not merely past :224 but past the OLD :2729 wall too. Attributed by reverting the one edit and rebuilding: without it, `:224 forward type not resolved: PEqualityComparerVMT`, frankS's exact symptom."
---

# The repro — refused by pin and HEAD alike, compiled by fpc

```pascal
program fwd;
{$mode objfpc}
type
  TFactory = class
  private type
    PPRec = ^PRec;      { <- reported here }
    PRec  = ^TRec;      { <- declared here }
    TRec  = packed record a: LongInt; end;
  public
    class function Go: LongInt; static;
  end;
class function TFactory.Go: LongInt;
var r: TRec; p: PRec; pp: PPRec;
begin r.a := 7; p := @r; pp := @p; Result := pp^^.a; end;
begin WriteLn('fwd ', TFactory.Go); end.
```

`fpc -Mobjfpc` prints `fwd 7`. pxx: `forward type not resolved: PRec`.

Measured across four spellings, all refused, so none of them is the boundary:
objfpc and delphi mode; as a program and as a unit interface. Pin v407 and HEAD
`4d1b041a7fc9` give the identical message, so this is not today's regression.

## Why it is filed apart from the regression it explains

The rtl-generics corpus contains this construct at `generics.defaults.pas:224`
and **used to compile past it** — the wall was at 2729 until `ad7c03b03`. So the
corpus case was being carried by something that commit removed. Fixing the
latent bug here would make the corpus immune to that, but the two questions are
different and only this one has a repro that stands on its own.

**Do not start debugging at the reported line.** The check is deferred:
truncating the corpus unit at line 236 and compiling it parses the same block
cleanly on both compilers. The line in the message is where the unresolved name
was USED, not where the failure is decided.


## Resolution (2026-09-09, frankZ) — the kind, not the depth

**The ticket's own repro pointed one step too narrow.** It shows
`PPRec = ^PRec; PRec = ^TRec; TRec = record`, which reads as a defect about
pointer-to-pointer chains. Chain depth is irrelevant. Measured, eighteen probes:

| forward target is a nested… | before |
| --- | --- |
| CLASS / RECORD | resolved |
| ARRAY | resolved |
| ENUM | resolved |
| **plain scalar ALIAS** | **refused** |
| **POINTER alias** | **refused** |
| **SUBRANGE** | **refused** |

and at UNIT level every one of them resolved. So the axis is the target's KIND
crossed with the declaration being NESTED — five passing and three failing, which
is a per-TABLE shape and not a per-construct one.

Declaration order is what made it look like a chain problem: with `PRec` written
*before* `PPRec` the same three types compiled throughout. A probe that happened
to use that order measured nothing. Both orders are asserted now.

### Cause — every arm was working

`DrainPendingPtrTargets` runs at the compilation unit's closing `end.`, and
`PendingPtrTargetResolved` asked:

1. `FindNestedType(PendPtrClassCi[i], nm)` — but `AddNestedType` is only ever
   called from `AddClassLikeType`, so the registry holds class-like nested types
   and nothing else.
2. then the flat table: `FindTypeAlias(nm)` — which filters candidates through
   `AliasVisibleHere` → `ClassOwnerVisibleHere`, and that reads
   `ParsingClassBodyCi`. **At the drain point `ParsingClassBodyCi` is -1.**

So `FindTypeAlias` answered, correctly, that a nested alias is not visible *from
here*. No arm errored; the scoped one was too narrow and the unscoped one was
asked from the wrong scope. `IsRecordType`, `FindArrayType` and `FindEnumType`
carry no owner column at all, which is the only reason those three kinds passed
— they cannot be asked a scoped question, so they answered a global one and
happened to be right.

That is "every instrument that lies, lies by being CORRECT ABOUT SOMETHING ELSE",
and it is why the reported line is not where the failure is decided — the ticket
already warned about that half.

### Fix — one predicate that already existed

`ClassDeclaresTypeNamed(ci, nm)` is exactly the question: *does this class, or an
ancestor, declare a type of this name.* Its own header records that
`FindNestedType` answers -1 for nested procedural, subrange, enum, array and
plain aliases, and that the `Alias*` table keyed by `AliasOwnerCi` is where those
rows live. It calls `FindNestedType` first, so nothing that resolved before can
stop resolving, and it walks the ancestor chain, which the two arms did not.

Two lines changed.

### Controls

`test/test_a_nested_forward_pointer_does_not_see_another_classes_type_fail.pas`
is the row that makes the fix correct rather than merely working: `PB` declared
in `TOther`, referenced from `TFactory`. **The easy wrong fix — falling back to
an unscoped alias scan — compiles that file.** fpc refuses it too, so it is
parity and not our own rule. A name declared nowhere is also still refused, but
that row cannot tell a scoped fix from an unscoped one, which is why it is not a
separate file.

### It clears the regression it was filed behind

[[bug-p-the-generics-corpus-wall-moved-backward-from-2729-to-224]] (frankH):
`generics.defaults.pas` now COMPILES and the driver RUNS (`drv ok`) — not merely
past `:224` but past the OLD `:2729` wall as well.

Attributed rather than assumed: I reverted the one edit with
`git checkout HEAD -- compiler/pasparser_decl.inc`, rebuilt, and got
`:224 forward type not resolved: PEqualityComparerVMT` — frankS's exact symptom
— then reapplied the patch and rebuilt to a byte-identical `4f4875267033`.

### There is no residual question — frankH settled it, and my note above was wrong

I closed this saying "whether something worth keeping was lost in `ad7c03b03` is
still frankH's question". It is not a question. frankH had already measured it,
on the full unit and before this fix:

1. **Identical input, both compilers fail at 224.** The smallest reproducing
   prefix (interface truncated at 884) prints `:224 forward type not resolved:
   PEqualityComparerVMT` under HEAD *and* under pin v407. **The pin fails it
   too, so `ad7c03b03` never caused the 224 failure** — it is this latent bug,
   which was already there.
2. **The drain runs after the whole unit parses** (`pasparser_prog.inc:2068`) —
   the same fact this fix is built on, read from the other side. So *reaching*
   that diagnostic means the unit parsed completely, and the line it names is
   where the `^T` was DECLARED.

Together: at `178270aba` the parse stopped at 2729 and the drain never ran; at
`ad7c03b03` the parse finishes and the drain finally speaks, about a declaration
2500 lines earlier. **The wall moved FORWARD, to the end of the unit. `224 <
2729` reads as backward only because one number is a stopping point and the other
is a declaration site.** Nothing was removed and nothing is owed a probe.

frankH notes one honest gap so nobody inherits it as an implied fact: they could
not reduce the pin's own wall (`System.Integer(ALeft) - System.Integer(ARight)`
inside `TCompare.UInt8` — standalone it compiles and prints 5 on both), so the
exact construct `ad7c03b03` unblocked was never identified. The two measurements
above stand without it.

## Log
- 2026-09-09 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 2242a5903.
