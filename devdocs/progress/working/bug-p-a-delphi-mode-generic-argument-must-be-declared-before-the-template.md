---
slug: bug-p-a-delphi-mode-generic-argument-must-be-declared-before-the-template
track: P
prio: 55
type: bug
status: working
blocked-by: []
summary: "In mode Delphi, `TE = TBox<TOuter>;` fails with `unknown type: TOuter` when TOuter is declared AFTER TBox in the same type section — reorder the two declarations and the identical program compiles and runs. FPC accepts both orders. DelphiRewriteGenericUses splices its minted alias declarations immediately behind the TEMPLATE, so they can only name types already declared at that point. objfpc is unaffected (its aliases are emitted at the use). 20-line repro, both orders."
owner: frankwasm
---


> **Lock released 2026-08-30 (frankP), fleet-wide pause before a re-pin — NOT
> abandoned.** Claimed, the anchor measured, then put back in `backlog/` because
> `working/` is a live lock and a lock behind a stopped session has to be chased
> by whoever runs the pin. Everything learned is in this file, not in a session:
> position **B** is the anchor (table above), the sketch that said otherwise is
> struck through with its measurement, and the three remaining cases are named.
> Nothing is half-applied — no compiler source was edited for this ticket.


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

## The sketch below was WRONG. Measured 2026-08-30 (frankP), all three positions.

**Struck through rather than deleted, because the wrong idea is the obvious one
and the next reader will have it too.** The sketch said: put the alias
declarations at the END of the enclosing type section, reusing
`EmitLateNestedSpecDecls`. That does not work, and the reason is visible the
moment it is tried instead of reasoned about — **the alias's own USE is inside
the same section, before the end of it.**

Three hand-written positions for the identical program, minted name spelled
`TBox_TOuter` because `$` is not lexable in source:

| # | where the alias declaration goes | result |
| --- | --- | --- |
| A | behind the TEMPLATE — **what pxx does today** | `unknown type: TOuter` |
| B | immediately before **the declaration that uses it** | **compiles, prints `8`** |
| C | at the END of the type section — **the sketch** | `unknown type: TBox_TOuter` |

A fails because the alias names a type declared later; C fails because the alias
is named by a declaration that comes earlier. **Only B satisfies both
constraints, and it is the only anchor that can** — the use site is legal Pascal,
so everything the group names is already declared there by construction, and
inserting immediately ahead of that declaration cannot outrun anything that
refers to the alias.

So the anchor is **the use site's own enclosing declaration**, not the section
end and not the template.

### What is left, and it is positional bookkeeping rather than design

The rewrite has the use's token index; it needs the start of the top-level
declaration containing it. That is not "scan back to the previous `;`" — a use
can sit in a class-body field (`F: TBox<TOuter>;`), where the nearest preceding
`;` is inside the class and a type declaration spliced there is nonsense. The
workable form is a FORWARD walk from the template's end to the use index,
tracking class/record/case depth, remembering the position after each depth-0
`;`; the last such position at or before the use is the anchor.

Cases that still need an answer before this is finished, none of them looked at:

- a use in a `var` / `const` section after the type section closed — there is no
  open type section to splice a bare `X = specialize ...;` into, so this needs
  the leading `type` keyword `EmitLateNestedSpecDecls` adds for exactly that
  reason;
- a use in a procedure body or parameter list;
- several tuples whose first uses are in different declarations — today they are
  emitted as one run at one point, and per-tuple anchoring makes them separate
  splices, each of which shifts every later index.

That last one is the reason this is not a small change: `insertAt` is a single
`var` cursor the fixed-point loop advances, and per-use anchoring turns one
ordered splice into several.

## Gate

`make compiler/pascal26` (the byte-identical self-host fixedpoint) + the repro in
both orders + `test/test_generic_qualified_arg_delphi.pas` (which pins the
working order and cites this ticket for the other). Track T sweeps the matrix.
