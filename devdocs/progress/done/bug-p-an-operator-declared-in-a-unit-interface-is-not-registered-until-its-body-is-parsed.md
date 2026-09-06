---
slug: bug-p-an-operator-declared-in-a-unit-interface-is-not-registered-until-its-body-is-parsed
title: "An operator declared in a unit INTERFACE is not registered until its implementation body is parsed, so a circular implementation-uses cannot see it"
track: P
prio: 35
type: bug
blocked-by: []
status: done
owner: frankS
created: 2026-09-05
summary: "`operator + (const a,b: op1) c: op1;` in a unit's interface registers nothing -- the overload enters the table only when the IMPLEMENTATION section's definition is parsed. A unit compiled while that implementation is still pending, which is exactly what a circular implementation-`uses` produces, sees the TYPE but not its operator and fails with `no operator overload found for record operands`. toperator1, toperator2, toperator3. Cross-unit operators themselves WORK; both non-circular controls are green. The fix is a synthesised-name scheme, not a patch: ParseOperatorDef names the routine `__op__` + OvrlCount, so an interface header and its implementation definition would be given different names and become two procs."
---

# The shape

Minimal repro, built and measured 2026-09-05 (all four files below plus a
driver; the full sources are five lines each):

    unit uc;                               unit ud;
    interface                              interface
    type op1 = record x,y: longint; end;   type op2 = record x,y: longint; end;
    operator + (const a,b: op1) c: op1;    operator + (const a,b: op2) c: op2;
    implementation                         implementation
    uses ud;                               uses uc;
    ... the definition ...                 ... the definition ...
    procedure UsesD;                       procedure UsesC;
    var a,b,c: op2;                        var a,b,c: op1;
    begin c := a + b; end;                 begin c := a + b; end;

`program drv; uses uc, ud;` gives

    pascal26:11: error: no operator overload found for record operands
      in: ud.pas

`PXXDBG=a.opovl` prints the order and it is the whole diagnosis:

    register op=70 left=(5,29) proc=__op__00      <- ud's own operator
    query    op=70 left=(5,28)  -> -1             <- uc's op1: nothing there yet
    register op=70 left=(5,28) proc=__op__01      <- uc's operator, too late

The TYPE resolves — there is no `unknown type` — and only the operator is
missing, which is what makes this specific to the operator table rather than to
unit loading.

# Controls, both green

Neither of these is affected, and they are why the title says *circular*:

* `uop` declares the operator in its interface and defines it in its
  implementation; `drv` uses `uop` and does `c := a + b`. Works.
* `ub`'s IMPLEMENTATION section uses `ua`, and `ua` carries the operator. Works
  — an implementation-`uses` is fine on its own. So is an interface-`uses`.

The single varying ingredient is the cycle.

# Why it is not a two-line fix

`pasparser_proc.inc`'s interface arm routes an `operator` header to
`SkipDeclHeaderToSemicolon`, and the comment there states the assumption that
fails: the operator "is registered from the IMPLEMENTATION section's definition
(which is parsed before any importer's body)". Under a cycle it is not.

Routing the interface header to `ParseOperatorDef` instead WOULD register it,
and that is the obvious patch — but `ParseOperatorDef` synthesises the routine's
name as `__op__` + `OvrlCount`. The interface header and the implementation
definition would therefore be given DIFFERENT names and become two procs: one
declared-and-never-defined, which `FindOpOverload2` returns because it is first,
and one carrying the body. The forward/body matching that every ordinary
`procedure Foo;` gets for free is exactly what a counter-derived name denies.

So the fix is a naming scheme, and it has to be a scheme rather than a patch,
because two operator declarations must collide in the name if and only if they
are the same declaration. The components that decide that — all available before
`ParseSubroutine` runs, and all but one already computed in `ParseOperatorDef`'s
own lookahead:

    opKey | left operand type name | right operand type name | param count | result type name

* **Param count** is the one not currently computed. It is `1 +` the number of
  `,`/`;` separators at paren depth 1 with bracket depth 0.
* **Arity has to be in the key.** `operator -(a: TFoo): TFoo` and
  `operator -(a, b: TFoo): TFoo` agree on every other component — `rightName` is
  read off the LAST colon, so it is `TFoo` for both.
* **The result type has to be in it too.** `operator :=(a: Integer): TA` and
  `operator :=(a: Integer): TB` are a legal pair that the duplicate-conversion
  check deliberately allows.

Registration then has to become idempotent. With the names matching,
`ParseSubroutine` attaches the body to the SAME proc, so the implementation pass
would otherwise add a second `Ovrl` row for it. Harmless for lookup — same proc
either way — but it would make the `:=`/`Explicit` duplicate-conversion check
fire on every interface-declared conversion operator, turning a fix into three
new refusals.

# Not the same as toperator78

toperator78 also fails at operator DECLARATIONS and for an unrelated reason:
operand types that are not aggregates at all (`operator ** (left, right:
LongInt)`, `operator and` over a set, `array of Char` operands), plus `**`
having no lexer token. Do not merge the two.

## The non-circular case works at HEAD — which the summary already says (frankS, 2026-09-05)

At `0bbd82cd7` (sha `7fca108e4b85`) a unit declaring `operator +` in its
interface, implementing it below, and used by a plain program prints the right
answer. That is **not** evidence about this ticket: the summary states the
failure needs a **circular implementation-`uses`**, and that *"both non-circular
cases work"*.

Recorded so the next staleness pass does not spend the minute again, and does
not bank the green. The probe that would settle this ticket has to build the
cycle; a straight `uses` cannot reach the condition.

## Log
- 2026-09-06 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 696d4a8ae.

## Resolved — 2026-09-06 (frankS), compiler `d3cc5b9b653d`

The interface arm of `ParseUnit` routes an `operator` header to
`ParseOperatorDef` instead of `SkipDeclHeaderToSemicolon`. That was only
possible once the synthesised proc name became a SCHEME rather than a counter:

    __op__<opKey:4>_<leftTypeName>_<rightTypeName>_<arity:2>_<resultTypeName>

Two declarations collide in that name if and only if they are the same
declaration, so the interface header and the implementation definition are ONE
proc — `ParseSubroutine` makes a forward from the bodiless header and attaches
the body to it, exactly as it already does for an ordinary interface `function`.

**ARITY IS THE LOAD-BEARING COMPONENT, and the new test proves it rather than
asserting it.** A unary and a binary `-` on one record agree on opKey, on both
operand type names (the right one is read off the LAST colon, so it is the same
name for both) and on the result type. With arity dropped from the name and the
compiler rebuilt, they collide into one proc and the test binary **SEGFAULTS**
on the unary row — not a wrong number, which is what makes it a control worth
keeping: the failure is unmissable and it is drawn from the population the
scheme is about.

Registration became idempotent through `OpOverloadRowExists` (symtab.inc), six
components with `procIdx` among them — that is what separates "the same
declaration seen twice" from "a genuine second operator with the same key",
which is the case the duplicate-conversion check exists to catch. The ticket
predicted this trap and it was real: without the guard, every interface-declared
`:=`/`Implicit`/`Explicit` would have been refused as a duplicate of itself.

- `toperator1.pp` burned: pxx rc=0, output byte-identical to fpc 3.2.2.
- New regression test `test_a_unit_interface_operator_is_visible_to_a_circular_uses.pas`
  with units `uopcirca` / `uopcircb`, both halves of the cycle exercised
  (each unit's body uses the OTHER unit's operator) plus the arity pair.
- `gate.sh quick` GREEN.

**Not touched, and named so the next reader does not merge them:** `toperator78`
and `terecs14` also fail at operator DECLARATIONS, for the unrelated reason the
ticket already recorded — `**` and `><` have no lexer token, so the header does
not parse at all. That is `lexer.inc`, shared with Track A.
