---
slug: bug-p-a-delphi-mode-generic-argument-must-be-declared-before-the-template
track: P
prio: 55
type: bug
status: backlog
blocked-by: []
summary: "In mode Delphi, `TE = TBox<TOuter>;` fails with `unknown type: TOuter` when TOuter is declared AFTER TBox in the same type section — reorder the two declarations and the identical program compiles and runs. FPC accepts both orders. DelphiRewriteGenericUses splices its minted alias declarations immediately behind the TEMPLATE, so they can only name types already declared at that point. objfpc is unaffected (its aliases are emitted at the use). 20-line repro, both orders."
owner: unassigned
---

# A mode-Delphi generic argument must be declared before the template

Found while fixing `bug-p-a-qualified-type-name-cannot-be-a-generic-argument`,
as the control that proved the two are unrelated. Filed separately because it
has nothing to do with qualified names.

## Repro — the SAME program in two declaration orders

FPC prints `8` for both. pxx compiles one and rejects the other.

```pascal
program q5;
{$mode delphi}
type
  TBox<T> = class          { template FIRST ... }
    V: T;
  end;

  TOuter = class           { ... argument type SECOND  -> pxx REJECTS }
    K: Integer;
  end;

  TE = TBox<TOuter>;
var
  e: TE;
begin
  e := TE.Create;
  e.V := TOuter.Create;
  e.V.K := 8;
  writeln(e.V.K);
end.
```

```
pascal26:5: error: unknown type: TOuter
  near: TOuter   class V  >>> TOuter  end
```

Swap the two type declarations so `TOuter` comes first and the identical program
compiles and prints `8`. The error line is `5` — inside `TBox`'s own body, at the
`V: T` field with `T` already substituted — which is the tell: the alias was
minted and spliced before `TOuter` existed.

## Cause

`DelphiRewriteGenericUses` emits `TBox$TOuter = specialize TBox<TOuter>;` at
`insertAt`, and for the pattern-A caller `insertAt` starts immediately behind the
template's own declaration. Everything the alias names must therefore already be
declared at that point. A Pascal type section imposes no such order — FPC
resolves the whole section — so any program that declares a helper type after the
generic that consumes it hits this.

objfpc does not have the problem: there the alias is not minted by the rewrite at
all, the `specialize` form is parsed where it is written, and prerequisites are
emitted at the use site.

## Why it is worth more than its repro suggests

"Declare the container before the thing it contains" is not a rule Delphi code
follows, and real Delphi-surface headers are ordered for readability. It is also
a SILENT-shaped failure from the author's point of view: the diagnostic points
into the TEMPLATE's body, at a line the author did not write, so the reported
location and the fixable location are nowhere near each other.

## Sketch, not a prescription

The alias declarations want to go at the END of the enclosing type section
rather than behind the template — which is what `EmitLateNestedSpecDecls`
already does for nested specializations, so the shape exists in this file and
should be reused rather than reinvented. The catch is that the rewrite runs
BEFORE the section is parsed and does not know where it ends; whoever takes this
should check whether the pattern-A caller can defer its splice to the point
`EmitLateNestedSpecDecls` uses, and say in the ticket which it chose.

## Gate

`make compiler/pascal26` (the byte-identical self-host fixedpoint) + the repro in
both orders + `test/test_generic_qualified_arg_delphi.pas` (which pins the
working order and cites this ticket for the other). Track T sweeps the matrix.
