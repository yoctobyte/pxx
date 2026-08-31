---
prio: 45
track: P
type: bug
status: backlog
blocked-by: []
found: 2026-08-30
found-by: frankA
summary: "A program declaring `TBox<T>` while also importing a unit that declares `TBox<T>` now parses, but every use resolves to the IMPORTED template: `b.Local` answers `no such member`. FPC takes the local declaration and prints 42. The declaration is parsed and then loses to the import."
---

# A generic declaration does not shadow an imported generic of the same name

## Repro

`u_a.pas`:

```pascal
unit u_a;
{$MODE DELPHI}
interface
type
  TBox<T> = record
    Imported: T;
  end;
implementation
end.
```

`drv.pas`:

```pascal
program drv;
{$MODE DELPHI}
uses u_a;
type
  TBox<T> = record
    Local: T;
  end;
var b: TBox<Integer>;
begin
  b.Local := 42;
  writeln(b.Local);
end.
```

```
pxx : pascal26:10: error: "Local": no such member on this record/class
      near:  TBox$Integer  begin b  >>> Local
FPC : 42
```

The minted specialization is `TBox$Integer` — built from **`u_a`'s** template.
The program's own `TBox<T>` was parsed and then lost.

## Why it is a bug and not a dialect choice

FPC compiles and runs it, and a later declaration shadowing an imported one is
ordinary Pascal scoping — nothing about the type being generic should change
it. Per CLAUDE.md's compat table this is the **"real Pascal source compiles
wrong, or not at all"** row: a bug in its own lane, not a compat item.

## Relationship to the rewrite fix

Split out of
[[bug-p-the-delphi-generic-rewrite-rewrites-a-shadowing-declaration-as-a-use]],
which fixed the **parse**: the declaration used to have `specialize` spliced in
front of it and died at `Expected: =`. It now parses, which is what makes this
second defect reachable at all — before the fix you could not get far enough to
observe it. Deliberately NOT folded into that ticket: one is a token rewrite,
the other is template registration/scoping, and merging them is what made the
first filing of that ticket wrong.

`test_generic_shadow_decl.pas` sidesteps this on purpose — both records declare
the same member name — so that test's result cannot depend on which template
wins. **A test asserting the shadowing SEMANTICS belongs with this ticket**,
and should use distinct member names, as the repro above does.

## Where to start

The template registry keyed by name: find where a template is registered and
looked up, and ask what happens when two units register the same name — most
likely first-registered wins, and the used unit is parsed first. Note the
durable fact from [[feature-pascal-corpus-expansion]]: `Tokens[]` is one array
shared by every unit and the main program is lexed FIRST, so "which came first"
is not the same question for tokens as it is for symbols.
