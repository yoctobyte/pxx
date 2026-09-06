---
slug: feature-p-a-generic-method-cannot-be-used-from-across-a-uses-clause
title: "A generic method works in one file and not across a uses clause, because the use sits behind the declaration in the token stream"
track: P
prio: 30
type: feature
blocked-by: []
status: working
owner: frankS
created: 2026-09-05
summary: "ExpandGenericMethod rewrites a generic method into one ordinary method per concrete type argument, and every edit it makes is at or ABOVE the class body. A program calling a USED UNIT\'s generic method is the shape where a use sits BELOW the declaration -- unit tokens are appended after the program\'s -- so the expansion bails out whole and the row still reports the old parse error. tgenfunc7 and tgenfunc9. The free ROUTINE already solved this, at the uses clause; the method needs the same move plus TokPos and DeclItem-span bookkeeping the routine did not."
---

# The shape

`0ee1e272f` made a generic method work in one file, both surfaces, instance and
class. It does that by rewriting the declaration, the definition and every use
into one ordinary method per concrete type argument, in the token stream,
before the class-body parser sees any of it.

Every one of those edits is at or above the class body, and the expansion
**bails out whole** if any use site sits below it. That is deliberate: a
removal behind `TokPos` invalidates `TokPos` and every `DeclItem` span already
recorded, and `AdjustPass2Spans` is a no-op outside the body pass, so a
half-rewrite would be worse than the parse error.

A use below the declaration is not exotic — it is what a program calling a used
unit's generic method looks like, because **a unit's tokens are appended after
the importing program's**. `tgenfunc7` and `tgenfunc9` are that shape and stay
skipped, with the reason on their `pxx.skip` rows.

# The precedent, and where it stops being one

The free ROUTINE has exactly this problem and solved it:
`SpecializeImportedGenericFuncUses` re-runs the sweep from the END OF THE USES
CLAUSE, *"the one site where 'every template this clause just imported is
registered, and every use of one lies ahead of here' is true"* — the same site
`DesugarImportedDelphiGenericUses` uses for the class side.

The method cannot simply borrow it. The routine sweep only REWRITES uses and
splices a body at the cursor; the method expansion also has to edit a CLASS BODY
that was already parsed, and the class is in the unit, behind the program. So
the shape is probably: register the generic method at class-parse time without
expanding, then expand at the uses clause the way the routine does — which
means the class needs to gain members after its body closed, and that is the
part nobody has measured.

# What to measure first

Whether a class can gain a method after `ParseTypeSection` has closed its body.
If it can, this is the routine's fix applied to a second lane. If it cannot, the
answer is probably to defer the whole class body rather than to expand in place,
and the estimate is very different. One afternoon either way, and it decides the
design.

# Gate

`tgenfunc7` and `tgenfunc9` compiling, each **diffed against fpc 3.2.2 output**
rather than scored on its exit code, plus the conformance fail list read BY
NAME (this area turns `%FAIL` rows red — `tgeneric31` and `tgenfunc14` both did
during the parent ticket), plus `make test` and the self-host fixedpoint.

## 2026-09-06 (frankS) — a corpus-free reduction, and the trigger is NOT what this ticket says

This ticket's only evidence was `tgenfunc7`/`tgenfunc9`, which live in
`library_candidates/fpc-testsuite` and are **not fetched in every checkout** —
mine has `busybox` and `sqlite` only. So here is the shape in two files anyone
can paste, and it reproduces at HEAD.

`u/ugm.pas`:

```pascal
unit ugm; {$mode objfpc}
interface
type TTest = class
       generic function Add<T>(a, b: T): T;
     end;
implementation
generic function TTest.Add<T>(a, b: T): T;
begin Result := a + b; end;
end.
```

```
pascal26:5: error: expected ':' before '>'
  in: ./u/ugm.pas
  near: class generic function Add < T >>> > ( a
```

### The trigger is ZERO VISIBLE USES, not the uses clause

| shape | free ROUTINE | METHOD |
| --- | --- | --- |
| declared and used in the same file | works | works (`0ee1e272f`) |
| **declared, NEVER used** | **works** | **parse error** |
| declared in a unit, used from the program | works | parse error |
| declared and used inside the SAME unit | works | **works** |

Row 2 is the new one and it removes the units entirely: **a PROGRAM that declares
a generic method and never calls it fails with the identical error.** No unit, no
uses clause, no use-below-the-declaration. Row 4 is its complement — put one use
inside the unit and the same unit compiles and runs.

So the cross-unit failure is not a distinct mechanism. It is row 2 wearing a
unit: the importing program's uses lie behind the unit in the token stream, the
sweep therefore sees NO uses, and with no uses it emits nothing and leaves the
`generic function Add<T>` header for the ordinary class parser, which cannot
read it.

That is consistent with `ExpandGenericMethod`'s own doc — *"a type argument
nothing asks for emits nothing, and an unused generic method's body is never
type-checked"* — but the doc treats emitting nothing as harmless, and it is not:
**emitting nothing also leaves the DECLARATION, and the declaration is not
ordinary Pascal.** The free routine, on the same "uses decide" design, does not
have this problem — row 2, measured.

### Which splits this ticket into two pieces of very different size

**(a) Zero uses must not be a parse error.** One file, no units, no span
bookkeeping: when the sweep finds no specializations, the generic declaration
and definition must be ERASED rather than left. Today a library unit that
declares generic methods for its consumers **cannot be compiled at all, even on
its own**, which is a harder blocker than the cross-unit call this ticket is
named for.

**(b) Uses that live in the importing program.** The actual feature, and the part
this ticket's "The precedent, and where it stops being one" section is about —
re-running at the end of the uses clause the way
`SpecializeImportedGenericFuncUses` does for the free routine, which needs a
class to gain members after `ParseTypeSection` closed its body.

**(a) does not fix (b)** — erasing an unused declaration makes the unit compile
and then the program's call finds no such method. But (a) is separable, much
smaller, and worth having on its own: it is the difference between "this unit
cannot be written" and "this unit can be written but not used generically from
outside".

### Not verified

- Whether a class can gain a method after `ParseTypeSection` has closed its
  body. That is the measurement this ticket names as first and I have not made
  it; it gates (b), not (a).
- Whether (a)'s erase is safe for the DEFINITION as well as the declaration —
  the definition sits in the implementation section and is found separately.
