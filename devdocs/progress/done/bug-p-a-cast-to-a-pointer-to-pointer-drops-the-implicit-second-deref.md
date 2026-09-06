---
track: P
prio: 70
type: bug
status: done
blocked-by: []
owner: frankB
summary: "RESOLVED 2026-09-06, together with bug-p-an-implicit-deref-over-a-typed-pointer-cast-is-dropped: ONE ARM, and the two tickets are the depth-2 and depth-1 faces of the same absent step. ParseLValueAST has carried the implicit-deref arm for as long as `p.a` has worked; ParseClassRecordSelectors -- THE SHARED WALKER the three postfix cast loops delegate to -- never had it, and its builder makes AN_FIELD and nothing else, so every caller that correctly delegated got a field applied to a POINTER VALUE. Fixed by that arm in the shared walker plus the C4 loop's delegation guard widened to hand over a pointer-valued `.` at all. THIS TICKET'S OWN DISCRIMINATOR WAS FALSE WHEN I MEASURED IT: it says only the CAST spelling is short a level, and the non-cast `pp^.a` was short a level too until frankA's b7b9e309e landed an hour later. Test: test_a_pointer_cast_dereferences_implicitly_for_a_selector, 8 rows, fpc 3.2.2's own output byte for byte. A third, distinct defect was split out rather than folded in -- bug-p-a-half-dereferenced-pointer-chain-answers-garbage-instead-of-refusing -- because its repair is a DIAGNOSTIC and not an address computation."
---

# A cast to a pointer-to-pointer drops the implicit second deref

## Repro — no class, no metaclass, 11 lines

```pascal
program r;
{$mode delphi}
type
  TRec  = record a, b: Integer; end;
  PRec  = ^TRec;
  PPRec = ^PRec;
var r: TRec; p: PRec; pp: PPRec;
begin
  r.a := 11; r.b := 22; p := @r; pp := @p;
  WriteLn('cast  a=', PPRec(pp)^.a, ' b=', PPRec(pp)^.b);
  WriteLn('deref a=', pp^^.a,       ' b=', pp^^.b);
end.
```

| | `PPRec(pp)^.a` / `.b` | `pp^^.a` / `.b` |
| --- | --- | --- |
| fpc 3.2.2 | 11 / 22 | 11 / 22 |
| HEAD `8c8fb55b6d26` | **4310376 / 0** | 11 / 22 |
| pin v404 | **4306248 / 0** | 11 / 22 |

`PPRec(pp)^` yields a `PRec` — a pointer. The `.a` selector then requires a
second, implicit dereference. pxx emits only the explicit one and applies the
field offset to the pointer value itself: `.a` is that value truncated to 4
bytes, `.b` is the 4 bytes past it.

## What the two rows tell you together

**The explicit `pp^^.a` spelling is correct**, so the record identity resolves
fine and `AliasPtrBaseRec` / the deref stamping are all doing their job. Only the
CAST-headed spelling is short a level. That localises this to the address
computation on the cast path, not to the alias table.

Order-independent and unchanged on the pin — so unlike the ticket this was split
from, **declaration order is not a factor here** and there is nothing to bisect.

## Do not reuse the class-ref probe

The shape was originally found as
`PPVMT(ppv)^.__ClassRef.Val(3)`, and that probe **cannot fail**: `Val` is a
CLASS function, resolved off the static class type, so it runs and returns 42
without ever dereferencing the garbage class-reference. Every "works" row
measured that way is uninformative. Use two distinct **Integer** fields, and read
**both** — `.a` sits at offset 0 and stays right even when the base is wrong, so
a one-field probe is green while the bug is live.

## Where it bites

`generics.defaults.pas:1865` and fifteen sibling lines, through
`{$DEFINE EXTENDED_HASH_FACTORY := PPExtendedEqualityComparerVMT(Self)^.__ClassRef}`.
That is the **cast** spelling, so corpus rung 6a is blocked on this ticket rather
than on the alias-repair fix that closed its former sibling.

## RESOLVED 2026-09-06 — the SHARED walker had no implicit-deref arm

`test/test_a_pointer_cast_dereferences_implicitly_for_a_selector.{pas,expected}`,
wired in the `Makefile`; `.expected` is fpc 3.2.2's own output byte for byte.

**ONE ARM, TWO TICKETS.** This and
`bug-p-an-implicit-deref-over-a-typed-pointer-cast-is-dropped` are the depth-2
and depth-1 faces of the same absent step, and both are fixed by the same
change. They were filed a day apart by two reporters, each saying explicitly
that it was not the other.

- `ParseLValueAST` (`pasparser_lval.inc:443`) has carried the implicit-deref arm
  for as long as `p.a` has worked.
- **`ParseClassRecordSelectors` — the SHARED walker, the one the three postfix
  cast loops delegate to precisely so they stop keeping private notions of what
  a `^` yields — never had it**, and its builder makes `AN_FIELD` and nothing
  else. So every caller that did the right thing and delegated got a field
  applied to a POINTER VALUE. The delegation was the remedy for four earlier
  tickets in this file and carried this hole into each of them.

The fix is that arm, in the shared walker's `tkDot` branch, plus the C4 cast
loop's delegation guard widened to hand over a pointer-valued `.` at all.

**THE TICKET'S OWN DISCRIMINATOR WAS DEAD BY THE TIME I MEASURED IT.** This
ticket says *"the explicit `pp^^.a` spelling is correct ... only the CAST-headed
spelling is short a level"*. When I ran the 2x2 — {cast, no cast} x {carets
written} — the NON-cast `pp^.a` was short a level too. frankA's `b7b9e309e`
landed underneath me an hour later and turned that row green; measured before
it, the cast was not the discriminator at all. Reasoning from the premise would
have aimed the fix at the cast path.

**WHAT COST THE MOST, and it is a scope error not a code one:** I first widened
the delegation guard, rebuilt, and nothing moved. The delegation was being taken.
The arm I was delegating TO was in a different function 2100 lines away in the
same file — I had read the arm at `:2561` and the walker at `:4683` in one
session without noticing they are not the same routine. *A file is not a scope*,
and "the shared walker has this arm" was a claim I had checked about the FILE.

**A THIRD DEFECT IS FILED, NOT FOLDED IN**, because its repair is a DIAGNOSTIC
and not an address computation:
`bug-p-a-half-dereferenced-pointer-chain-answers-garbage-instead-of-refusing` —
`ppp^.a` on a three-deep pointer compiles and prints 4310376 where fpc says
`Illegal qualifier`. Pre-existing on pin v404 and unchanged by this fix.

Controls: rows E..H are every spelling where the dereference is WRITTEN OUT.
The change INSERTS a dereference, so what it can break is inserting a SECOND one
where the caret already did the job, and only a row that already dereferences can
catch that. Row B is a METHOD call — the walker reaches its method arm only once
the receiver has become a record, so a fields-only fix prints every number
correctly and still calls `Sum` with a pointer as Self.

## Log
- 2026-09-06 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
