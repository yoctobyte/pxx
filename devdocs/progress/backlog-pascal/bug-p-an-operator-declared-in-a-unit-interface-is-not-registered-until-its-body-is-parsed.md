---
slug: bug-p-an-operator-declared-in-a-unit-interface-is-not-registered-until-its-body-is-parsed
title: "An operator declared in a unit INTERFACE is not registered until its implementation body is parsed, so a circular implementation-uses cannot see it"
track: P
prio: 35
type: bug
blocked-by: []
status: backlog
owner: ""
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
