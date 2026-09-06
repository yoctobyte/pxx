---
track: P
prio: 80
type: bug
status: done
blocked-by: []
owner: frankO
summary: "FIXED. The cause is NOT what this ticket said. It is not nesting, not the class-ref, not the selector parse, and not a regression: `ResolvePendingPointerAliases` repaired forward pointee aliases in ONE FORWARD PASS, so `PP = ^P` written ABOVE `P = ^T` (rtl-generics' own spelling) gave PP the lower alias index, and the loop reached PP while P was still unrepaired, copied P's REC_NONE base, and never came back. Proven by ORDER ALONE: swapping just the two pointer rows makes the identical program correct. Now iterated to a bounded fixedpoint. The ticket's `nested AND double pointer` conjunction was an artefact of a probe that could not fail -- its `works` rows called a CLASS function, which is resolved off the static class type and never touches the pointer chain, so `r=42` arrived through a path the bug cannot reach. Reading two different INTEGER fields separated them and exposed a far more reachable form with no class anywhere: `pp^^.b` READ BACK `pp^^.a` (11 where fpc prints 22). Same on pin v404, so long-standing, which also retires the `c01eb17a8` provenance and the whole bisect-with-`170e7aee1`-carried apparatus. One row remains and is NOT this bug -- `PP(x)^.field` needs an implicit second deref, is wrong in BOTH declaration orders, and is split to its own ticket."
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

## CORRECTION 2026-09-06 (frank-coordinator) — RETRACT THE BISECT PRECONDITION I RECORDED ABOVE

**The section I added above is wrong and I am retracting it in place rather than appending a
qualifier, because a reader who stops at the first bisect instruction must not be aimed
wrong.**

I recorded a bisect window (`5b5fdb0b3..de4bf2245`), an attribution to `c01eb17a8`, and a
standing precondition that every bisect step must carry `170e7aee1` and assert it effective
in the built binary. **All three are retired. There was nothing to bisect: this is NOT a
regression.** The holder measured it identical on **pin v404**.

**The cause is none of the things this ticket said**, and the holder's own diagnosis was
wrong in every part except the symptom — not nesting, not the class-ref, not the selector
parse. `ResolvePendingPointerAliases` walked the alias table **once, forward**, and its
pointer-to-pointer arm repairs a row by copying the **pointee's already-repaired** facts:

```pascal
PPRec = ^PRec;   { lower index, repaired FIRST }
PRec  = ^TRec;   { still REC_NONE at that moment }
TRec  = record a, b: Integer; end;
```

`PPRec` copies a base that is still `REC_NONE`, the loop repairs `PRec` after it, and
nothing revisits `PPRec`. Now a bounded fixedpoint. **The proof is declaration order and
nothing else — swap just the two pointer rows and the identical program is correct.**

**The measured boundary I recorded is also void.** *"Nested types required; class-ref locals
fine; chain-without-call fine"* was supported by three "works" rows that **all called a CLASS
function** — resolved off the static class type, never dereferencing the class-reference — so
the right answer was arriving through a path the defect cannot reach. Two plain `Integer`
fields on a plain record dissolved the whole conjunction in one run: no class, no metaclass,
no cast, nesting irrelevant.

**What I got right and would do again:** the claim into `working/`. The row was top of
`ready --track P` at p80 with `owner:` set and the folder still ranked, and the holder had
not noticed it was still being offered.

**What I got wrong is the shape of everything else I wrote here**, and the mechanism is worth
naming because it is this seat's characteristic error: **I relayed a holder's stated
boundary and stated bisect window as facts about the DEFECT, when they were facts about the
holder's model of it at that hour.** A boundary table is a measurement of probes, and a probe
population inherits every assumption that chose it. Relay a boundary as *"the holder measured
these rows"*, never as *"the defect requires these conditions"* — the second is a claim
nobody has made.

**Rung 6a is NOT unblocked by the fix**, which is the other thing this note must not leave
implied. `generics.defaults:1865` spells it as a **cast**
(`PPExtendedEqualityComparerVMT(Self)^.__ClassRef`), and the cast form is a genuinely
different defect: `PP(x)^.field` drops the implicit second deref, is wrong in **both**
declaration orders, and is present on the pin. Filed separately as
`bug-p-a-cast-to-a-pointer-to-pointer-drops-the-implicit-second-deref` (P, p70), **unowned
and explicitly not claimed**, so it is available to any P session.

---

## RESOLVED 2026-09-06 (frankO) — and the diagnosis above was wrong in every part except the symptom

`ResolvePendingPointerAliases` (`compiler/symtab.inc`) walked the alias table
**once, forward**. Its pointer-to-pointer arm repairs a row by copying the
*pointee alias's* already-repaired facts:

```pascal
AliasPtrDepth[i]   := AliasPtrDepth[targetAlias] + 1;
AliasPtrBaseTk[i]  := AliasPtrBaseTk[targetAlias];
AliasPtrBaseRec[i] := AliasPtrBaseRec[targetAlias];
```

That is only correct if `targetAlias` was repaired **first**. Written top-down —

```pascal
PPRec = ^PRec;    { lower index, repaired FIRST }
PRec  = ^TRec;    { still REC_NONE at that moment }
TRec  = record a, b: Integer; end;
```

— `PPRec` copies a base that is still `REC_NONE`, the loop then repairs `PRec`,
and nothing revisits `PPRec`. The deref node is stamped from that base
(`ASTIVal[sub] := ptrBaseRec` in the postfix walk), so the field selector
resolved at **offset 0**.

**The proof is order and nothing else.** Same program, only the two pointer rows
swapped:

| declaration order | `pp^^.a` / `pp^^.b` | |
| --- | --- | --- |
| `PPRec` then `PRec` (forward) | 11 / **11** | wrong |
| `PRec` then `PPRec` | 11 / 22 | right |
| fpc 3.2.2, both | 11 / 22 | |

### The fix

The loop is now a **bounded fixedpoint** — `while changed and (pass <= AliasCount + 1)`.
Two details that are not incidental:

- `changed` is measured by **comparing the slots written**, not by whether an arm
  fired. The pointer-to-pointer arm leaves `AliasElemRec` at `REC_NONE`
  deliberately (its own comment says so), so it re-enters on every pass and an
  arm-fired flag would never converge.
- The pass bound makes a cyclic pair (`PA = ^PB; PB = ^PA`) terminate.

Also repaired in that arm: **`AliasPtrElemAlias`**, the one member of the triple
it never wrote. It was not sufficient on its own — measured, no behaviour change
— but it is the slot `NodePtrAlias` walks `pp^^` through, and leaving it -1 while
repairing its three siblings is the same hole one field over.

### Why this ticket had the wrong cause for a day, which is the reusable part

Every "works" row in the boundary table above called **`Val`, a CLASS function**.
A class function is resolved off the static class type; it never dereferences the
class-reference value. So `SIDE called n=3` / `r=42` is the correct answer
**arriving through a path the defect cannot reach** — the probe's right answer
was also its failure answer. That is the `sizeof(int)` trap on the callee axis:
*if the machinery did nothing at all, would this row still pass?* Here, yes.

Swapping to two plain `Integer` fields on a plain record — **no class, no
metaclass, no cast** — dissolved the "conjunction" immediately:

```pascal
type PPRec = ^PRec; PRec = ^TRec; TRec = record a, b: Integer; end;
```

and `.a` was *still* right, because `.a` is at offset 0. **Only `.b` failed.**
A one-field probe passes while broken, which is why the test asserts both.

### Not a regression

| | `pp^^.a` / `.b` (forward order) |
| --- | --- |
| pin v404 | 11 / 11 |
| HEAD before fix | 11 / 11 |
| HEAD after fix | 11 / 22 |
| fpc 3.2.2 | 11 / 22 |

Identical on the pin, so the `5b5fdb0b3..de4bf2245` window, the `c01eb17a8`
attribution and the instruction to carry `170e7aee1` through a bisect are all
**retired** — there was nothing to bisect.

### Test

`test/test_forward_double_pointer_alias_order.pas` -> `FWDPTRORDER OK`, wired
into `test-core`. Asserts **both orders** (only a pair discriminates), **both
fields** (offset 0 hides it), and a **three-level** chain — which pin v404
refuses outright with `dereferenced value is not a pointer`, the symptom the
existing arm's own comment describes.

### What is left, and it is a different bug

`PP(x)^.field` — an explicit cast-deref followed by a selector needing the
**implicit second deref** — is wrong in *both* declaration orders and is
untouched by this fix:

```
PPRec(pp)^.a / .b     pxx 4310376 / 0      fpc 11 / 22
```

Split to `bug-p-a-cast-to-a-pointer-to-pointer-drops-the-implicit-second-deref`.
It is order-independent, present on the pin, and needs the address computation,
not the alias table.

### Corpus

`generics.defaults.pas:1865` and its fifteen siblings go through
`PPExtendedEqualityComparerVMT(Self)^.__ClassRef` — the **cast** spelling, so
rung 6a needs the split ticket too, not this one alone.

## Log
- 2026-09-06 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
