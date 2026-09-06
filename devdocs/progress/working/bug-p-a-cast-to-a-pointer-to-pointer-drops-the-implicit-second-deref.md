---
track: P
prio: 70
type: bug
status: working
blocked-by: []
owner: frankB
summary: "`PP(x)^.field` where PP is a pointer-to-POINTER alias applies the field offset one indirection too early: the explicit `^` is emitted and the IMPLICIT second deref the selector requires is not, so `.a` reads the intermediate pointer VALUE as if it were the record. Measured against fpc 3.2.2: `PPRec(pp)^.a` / `.b` give 4310376 / 0 where fpc gives 11 / 22. A SILENT WRONG VALUE on a program both compilers accept. Order-INDEPENDENT (both declaration orders, unlike its former sibling) and identical on pin v404, so long-standing. The explicit spelling `pp^^.a` is CORRECT, which is the discriminator: the record identity is resolved fine and only the address computation is short a level. Split out of bug-p-a-class-method-through-a-class-ref-field-is-parsed-as-a-field-read, which turned out to be a different cause (a one-pass alias repair) and is fixed; this is the half that blocks corpus rung 6a, because generics.defaults spells it as a CAST."
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
