---
slug: feature-p-a-generic-method-cannot-be-used-from-across-a-uses-clause
title: "A generic method works in one file and not across a uses clause, because the use sits behind the declaration in the token stream"
track: P
prio: 30
type: feature
blocked-by: []
status: done
owner: frankS
created: 2026-09-05
summary: "TWO Exits in ExpandGenericMethod produced one identical parse error, and only one is left. ZERO USES is FIXED (this ticket, below): a unit or program that merely DECLARED a generic method it never called could not compile at all, because emitting nothing also left the raw header in the stream -- the zero-specialization path now erases both halves. WHAT REMAINS is the named row: a use sitting BELOW the declaration, which is what a program calling a used unit's generic method looks like. The sweep DOES find that use, so it exits at the SCOPE guard instead, and moving it needs TokPos and DeclItem-span bookkeeping the free routine never needed. tgenfunc7 and tgenfunc9."
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

## 2026-09-06 (frankS) — the zero-uses half is FIXED

`ExpandGenericMethod`'s `if nSpec = 0 then Exit;` now erases the declaration and
the definition instead of leaving them. It reuses the removal the expansion
performs anyway two dozen lines below, in the same descending order — definition
first, so removing the declaration cannot shift an index the definition still
needs — and with no specializations there is simply nothing to splice back.

Rows, measured, `-Futest/generic_unused_units`:

| shape | pinned | HEAD |
| --- | --- | --- |
| unit declares a generic method, nothing anywhere calls it | `ugmun.pas:10 expected ':' before '>'` | compiles |
| program declares one, never calls it | same error | compiles |
| Delphi surface (`function Add<T>`, no `generic` keyword), unused | same error | compiles |
| `class generic function`, unused | same error | compiles |
| used and unused generic method in ONE class | — | used one still expands |
| ordinary members either side of the erased pair | — | both survive |
| a use across a uses clause | error | **still the same error** |

Test `test/test_generic_method_unused_is_erased.pas` + `test/generic_unused_units/`,
wired into `test-core`. Every row doubles as a neighbour check, because the erase
spans two ranges in two sections and one token too many takes an ordinary member
with it.

### The guess this corrected

I wrote in the fix's own comment that the cross-unit row's diagnostic would move
off the declaration and onto the call, then measured it and it does not. **The
sweep scans the whole token stream**, so a use in the importing program IS found
even though it sits at a lower index; `nSpec` is therefore >= 1, the zero-uses
block is never reached, and the SCOPE guard exits exactly as before. The comment
was corrected before the commit. Two Exits, one error message, and the only way
to tell which one you are looking at is to count the uses.

## What is left, and it is the whole named row

The SCOPE guard — `if useName[u] <= implEnd then Exit`. Unchanged, and the
prerequisite this ticket names is still unmeasured:

> Whether a class can gain a method after `ParseTypeSection` has closed its body.

That is what re-running the expansion at the end of the uses clause requires,
the way `SpecializeImportedGenericFuncUses` does for the free routine. The free
routine did not need it because a free routine is not a class member. So the
precedent covers the SWEEP-LATER shape and stops exactly where the member does.

## 2026-09-06 (frankS) — the named row is DONE, and its stated prerequisite was not one

`1364d9542`. A generic method declared in a unit and called from the importing
program now compiles and runs, on both surfaces.

### The prerequisite this ticket names does not exist

> *What to measure first: Whether a class can gain a method after
> `ParseTypeSection` has closed its body.*

It never has to. **The sweep scans the whole token stream, so when the unit's
class body is parsed the program's uses are already visible** — measured, and it
is what the earlier entry recorded without drawing the conclusion: this shape
reached the SCOPE guard with `nSpec >= 1`, not the zero-uses path. So the
specialization set is known at declaration time, the members are emitted there,
and every one of those edits is above the class body where they were always
safe.

**The only thing behind `TokPos` is the CALL.** So the only thing deferred is
renaming it, and the answer is the free routine's own answer, at the same site:
`SpecializeImportedGenericMethodUses` beside `SpecializeImportedGenericFuncUses`
at the end of the uses clause. It rewrites and emits nothing.

That is why the estimate in this ticket was too big. The precedent covered more
than "the sweep-later shape" — it covered the whole problem, because the part
that looked method-specific (a class member) turned out not to be on the
deferred path at all.

### AHEAD OF TokPos ONLY — the bound is the fix, not a tidy-up

The sweep fires at the end of *every* uses clause, including one **inside an
imported unit**, and there the importing program's body is at LOWER indices.
Sweeping the whole stream removed tokens behind `TokPos` and shifted `TokPos`
itself: `expected ':' before ';'` inside a `var` section three lines away, a
diagnostic with nothing to do with generics. Nothing is lost by stopping —
a use behind this point is ahead of the importing file's own clause, and the
program's body is ahead of the program's own, which runs last.

### And `class generic function` had never worked at all

Found while widening, not looked for. FPC writes `class` before `generic`;
`GenericKwAt` walked back over `generic` only, so the expansion re-read the
member from `function` and emitted an ORDINARY method:

    TZ.specialize Twice<Integer>(21)
    -> cannot call non-static method on class type directly

**in one file, at the pin.** Fixed by walking back over both keywords and
capturing the header from the same token the removal starts at — three bounded
steps and deliberately not a loop, because a loop eats the class declaration's
own `class` when a generic method is the first member and deletes the type.

### Rows

`test/test_generic_method_across_a_uses_clause.pas` + `generic_xunit_method_units/`,
wired as `test_gen_xmeth26`: objfpc `specialize` across a uses clause; two
different type arguments for one method; the bare `t.Add<Integer>` spelling; a
class generic method across the clause and in-file; the Delphi surface; and a
UNIT calling another unit's generic method with the program never naming it.

One hypothesis measured false: that the next member absorbs a leftover `class`
keyword. A method reading an instance FIELD returns 77, so it does not.

### Not claimed

`tgenfunc7` and `tgenfunc9` are still `pxx.skip` rows. They live in
`library_candidates/fpc-testsuite`, which this checkout does not have — and per
frank-coordinator that is UNFETCHED rather than scarce
(`tools/install_lib_candidates.sh fpc-testsuite`, present in four trees on this
box). Their skip lines should be re-measured by whoever next fetches it; the
mechanism they were skipped for is fixed.

## Log
- 2026-09-06 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
