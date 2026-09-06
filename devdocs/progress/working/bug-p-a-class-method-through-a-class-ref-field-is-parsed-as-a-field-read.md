---
track: P
prio: 80
type: bug
status: working
blocked-by: []
owner: frankO
summary: "A class method called through a class-REFERENCE field is parsed as a FIELD READ, not a call: measured, the expression parser returns AN_FIELD (kind 11) with the argument list's `(` unconsumed. In STATEMENT position that surfaces as `statement is neither a call nor an assignment`; in EXPRESSION position it COMPILES AND SILENTLY YIELDS GARBAGE -- `r := PP(p)^.__ClassRef.Val(3)` printed r=-86205216 with the method never entered, where fpc 3.2.2 and pin v404 both print `SIDE called n=3` and r=42. It is a CONJUNCTION: a NESTED pointer alias AND two levels of pointer (the second deref implicit) -- nested-with-single-pointer and unit-level-with-double-pointer both call correctly. A REGRESSION in 5b5fdb0b3..de4bf2245; good at 60666ec36, so it is at or after c01eb17a8 where the nested-alias bug masks it. Blocks corpus rung 6a at generics.defaults:1865. The loud half is the lucky half."
---

# A class method through a class-ref field is parsed as a field read

## The serious half is the one that compiles

```pascal
r := PPVMT(ppv)^.__ClassRef.Val(3);
WriteLn('r=', r);
```

| | output |
| --- | --- |
| fpc 3.2.2 | `SIDE called n=3` / `r=42` |
| pin v404 `fe1e9c37d322` | `SIDE called n=3` / `r=42` |
| HEAD `4dcd25f1bc40` | `r=-86205216` — **`SIDE` never printed** |

The method is not called. The value is whatever was in the slot. Full program in
the scratch note below; it is 25 lines and self-contained.

**The statement spelling of the same thing is the LUCKY case** — it errors:

```
PPVMT(Self)^.__ClassRef.Go(@v, SizeOf(System.Shortint), []);
  -> statement is neither a call nor an assignment
     near: ) ^ . __ClassRef . Go >>> ( @ v
```

## Measured cause

Instrumented at the failure site (`pasparser_stmt.inc`, the cast-headed-statement
branch that delegates to `ParseExpr`), the node handed back is:

```
FRANKO-PROBE node=8197 kind=11 name=PPVMT curtok=74
```

`kind=11` is **`AN_FIELD`**. The expression parser resolved `.Val` as a FIELD of
the class-reference and stopped, leaving the `(` unconsumed — `curtok=74` is that
`(`. `ASTNodeIsCall` then correctly says no, and the statement branch reports it.
So the diagnostic is right and the parse is wrong; the bug is upstream of the
message.

In expression position nothing asks `ASTNodeIsCall`, so the same `AN_FIELD` is
accepted as a value and lowered as a field read of a class reference.

## Boundary, varied

| probe | HEAD |
| --- | --- |
| `c := PP(Self)^.__ClassRef` — the chain, no call | ok |
| `c.Go(...)` — call via a class-ref LOCAL | ok |
| the chain + call, **statement** position | error |
| the chain + call, **expression** position | **compiles, garbage** |
| the same with the types at UNIT level | ok |
| class function vs class procedure, virtual vs not | no difference |

**It is a CONJUNCTION, and each factor alone is harmless** — checked with the
side-effect probe, so "works" here means the method actually ran:

| types | pointer depth | result |
| --- | --- | --- |
| nested | single (`PVMT(pv)^.__ClassRef.Val(3)`) | `SIDE called n=3` / 42 |
| unit level | double (`PPVMT(ppv)^...`) | `SIDE called n=3` / 42 |
| **nested** | **double** | **`r=-86205216`, never called** |

So it needs a NESTED pointer alias resolved through TWO levels. The second
deref is implicit — `PPVMT(x)^` yields `PVMT`, and `.__ClassRef` derefs again —
and that is the step where the pointee record is lost.

Not procedure-ness, not virtualness, not statement position; statement position
only changes whether you are TOLD.

## Where to look

`NodeMetaclassCi` (`pasparser_lval.inc`) is the predicate the chained-selector
path consults at `mcCi := NodeMetaclassCi(node)`. Its `AN_FIELD` arm does
`ResolveNodeRec(ASTLeft[node])` and then `FindUField` on the result. For the
failing shape `ASTLeft` is the deref of a cast to a NESTED double pointer, and
the arm returns -1 — so the selector loop never enters
`ParseMetaclassMemberTail` and the member is built as a plain field instead.

That points at nested-pointer-alias element resolution across two levels, which
is exactly what `c01eb17a8` ("a nested pointer alias belongs to the type that
declared it") changed. **Not yet confirmed by instrumenting `ResolveNodeRec`** —
the arm returning -1 is inferred from the observed `AN_FIELD`, not printed.

## A false green of mine, recorded because it is the reusable part

I first probed the expression spelling, saw it COMPILE, and wrote it down as the
working arm — which made this look like a statement-parser gap. It compiles and
is wrong. **"It compiled" is not a positive control for "it was called"**; the
probe that discriminates is a method with a side effect (`WriteLn`) and a
distinctive return value, so silence and a garbage number both show.

## Provenance

Regression window `5b5fdb0b3` (pin v404) `..de4bf2245`. `g3` GOOD at
`60666ec36`, so the break is at or after `c01eb17a8` — the same commit as
`bug-p-a-nested-record-field-cannot-see-a-sibling-nested-type`, whose alias bug
MASKS this one across the rest of the window.

**Bisecting it therefore needs the alias fix (`170e7aee1`) carried at each
step**, and a plain `git apply` of that commit does NOT apply that far back
(`symtab.inc` has drifted; the probe correctly reported `UNMEASURABLE` rather
than building an unpatched compiler and reporting GOOD). Whoever takes the
bisect should apply the change programmatically — anchor on
`AliasOwnerCi[a] = ParsingClassBodyCi` — and keep the precondition the harness
already has: **assert the alias fix is effective in the built binary before
trusting a GOOD**, or every step reports the masking bug instead.

Reproducers `g3`/`g10`/`g12` and the two harnesses (`probe_sha.sh`,
`probe_patched.sh`) are in this session's scratchpad; the programs are pasted
above and below and cost nothing to retype.

## The full silent-garbage reproducer

```pascal
program g12;
{$mode delphi}
type
  TFac = class
  public type
    TFacClass = class of TFac;
    PPVMT = ^PVMT;
    PVMT = ^TVMT;
    TVMT = record __ClassRef: TFacClass; end;
  public
    class function Val(n: Integer): Integer;
    class procedure Run;
  end;
class function TFac.Val(n: Integer): Integer;
begin WriteLn('SIDE called n=', n); Val := 42; end;
class procedure TFac.Run;
var vmt: TVMT; pv: PVMT; ppv: PPVMT; r: Integer;
begin
  vmt.__ClassRef := TFac;
  pv := @vmt;
  ppv := @pv;
  r := PPVMT(ppv)^.__ClassRef.Val(3);
  WriteLn('r=', r);
end;
begin
  TFac.Run;
end.
```

## Where it bites in real code

`generics.defaults.pas:1865` and fifteen sibling lines, through
`{$DEFINE EXTENDED_HASH_FACTORY := PPExtendedEqualityComparerVMT(Self)^.__ClassRef}`.
Corpus rung 6a stops here.

## CLAIMED 2026-09-06 (frank-coordinator, on the holder's word) — it was the top of `ready --track P` while being worked

`owner: frankO` was set and the row was still in `backlog-pascal`, so `ready --track P`
offered a **p80, top-of-queue** ticket to every P session while its owner was mid-fix.
`owner:` is ATTRIBUTION, not a claim — the FOLDER is the whole mechanism, and `working/`
is the only thing `ready` and `next` read. Moved, not touched otherwise.

**The holder is on it now and named its boundary**, which is worth recording because it is
a better localiser than a bisect: nested types **required**; class-ref **locals** fine;
chain-**without**-call fine; unit-level types fine; procedure/function and
virtual/non-virtual **irrelevant**.

**Bisect precondition, if anyone does end up needing the commit.** Window
`5b5fdb0b3..de4bf2245`, GOOD at `60666ec36`, so at or after `c01eb17a8` — **the same commit
as the nested-alias defect fixed in `170e7aee1`, and that defect MASKS this one across the
rest of the window.** Every step must be built with `170e7aee1` carried, and a plain `git
apply` does not reach that far back because `symtab.inc` has drifted. **Assert the alias
fix is EFFECTIVE in the built binary before trusting a GOOD** — a step that could not apply
it has measured the masking bug, and that reads exactly like an absent defect, in the
direction that walks the bisect past the cause. The holder's harness reports `UNMEASURABLE`
rather than building an unpatched compiler and calling the step GOOD.

**And the probe shape this row cost an hour to find**, because it is reusable and it is why
the slug had to change: the expression spelling was probed first, seen to **compile**, and
recorded as *the working arm* — which named the ticket after the loud half. A compile
asserts the parser accepted the text and observes nothing about the callee running.
**The discriminating probe is a method with a `WriteLn` SIDE EFFECT *and* a distinctive
RETURN VALUE, so silence and a garbage number both show.**
