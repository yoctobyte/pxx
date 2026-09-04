---
prio: 45
track: P
type: bug
status: done
blocked-by: []
found: 2026-08-30
found-by: frankA
summary: "FIXED 2026-09-04. Two mechanisms, each covering a case the other does not, both proved load-bearing by ablation. (1) DesugarImportedDelphiGenericUses mints the alias AT THE USES CLAUSE -- DGenDeclAnchor returns the clause itself for that caller -- so it was parsed before the importing file's own type section existed; now skipped for a name this file also declares ahead of the clause. (2) Once the imported unit specializes it too, ParseSpecialization's 'an exact re-statement is a no-op' shortcut compared templates by NAME, which is equal for two different templates sharing a spelling, and consumed the local declaration as a duplicate; now keyed on the Templates[] index (SpecTemplateIdx[]). Nothing in symbol lookup or unit visibility changed. Both surfaces and all three shapes match fpc 3.2.2 (42 / 42 11 / 42 11 33 4)."
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

## Log
- 2026-09-04 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 01998adb8.

## Fixed 2026-09-04 (frankB) — and it was not the lookup

The ticket's "where to start" pointed at the template registry keyed by name and
asked what happens when two units register the same name. That is the right
place to look and the wrong answer: **`Templates[]`'s by-name lookup already
prefers the LAST arity-matching entry, which is the local declaration.** It never
got the chance to answer.

### Mechanism 1 — the alias was minted before the local template existed

`DesugarImportedDelphiGenericUses` runs at the end of `ParseUsesClause` and
mints `TBox$Integer = specialize TBox<Integer>;` **there**. That is not
incidental: `DGenDeclAnchor`'s own comment says *"when fromIdx is not in a type
section at all (the imported-unit caller splices after a `uses` clause) ... the
answer is fromIdx — today's position"*. So the alias declaration is PARSED
before the importing file's own type section is reached, and the name resolves
against the only template registered at that moment — the import. The file's own
`TBox<T>` was parsed afterwards and had nothing left to bind.

Both surfaces go through it: `PXXDBG=p.mint:*` prints one `dgen` mint for the
mode-Delphi `TBox<Integer>` and one for the objfpc `specialize TBox<Integer>`,
so this was never a Delphi-surface problem.

Fixed by not answering too early: the sweep skips a template whose name **this
file** also declares ahead of the clause (`TemplateShadowedByThisFile` /
`FileDeclaresTemplateAhead`). The local declaration's own sweep then mints it,
after registration, where the existing lookup picks the local one. **The file
test is load-bearing and not decoration** — every used unit's tokens are
appended AFTER the file that used it, so a plain forward scan from a program's
uses clause walks into the imported unit's own declaration and answers "yes,
this file declares it" about the wrong file. `PasSrcOfTok` is the discriminator.

### Mechanism 2 — the minted name is not an identity

Skipping is not enough the moment an imported unit **specializes the template
itself**. `ugshadowa` writing `var b: TBox<Integer>` mints `TBox$Integer` in its
own scope; when the program then mints its own, `ParseSpecialization`'s "an
exact re-statement of the same declaration is a no-op" shortcut fired —
because it compared `Specializations[si].TemplateName` to `templateName`, and
those are **equal strings for two different templates that share a spelling**.
The program's declaration was consumed as a duplicate.

`SpecTemplateIdx[]` records the `Templates[]` index each specialization was
minted from, and the shortcut now compares that. A genuine re-statement still
short-circuits; a collision between two templates named alike no longer does.

### Ablation — both halves measured, neither assumed

| build | `drv2` shadow | `drv2c` + A specializes | `drv2b` three-way |
| --- | --- | --- | --- |
| before | FAIL | FAIL | FAIL |
| mechanism 1 only | **42** | FAIL | FAIL |
| mechanism 2 only | FAIL | FAIL | FAIL |
| both | **42** | **42 11** | **42 11 33 4** |

Mechanism 2 alone changes nothing, because the alias is still minted at the uses
clause and the local template is not registered yet. Mechanism 1 alone stops at
the first row. The middle row of that table is the reason the test unit
specializes its own template rather than merely declaring it.

### Not touched

Symbol visibility, unit scope, `uses` handling: nothing outside
`pasparser_generic.inc` and one array in `defs.inc`. frankD was told directly
before the change, since this brushes their unit-scoping slice.

### Test

`test/test_generic_shadow_import.pas` + `generic_shadow_units/` — a program and
two units, three distinct templates named `TBox` live at once, **each with a
DIFFERENT member name** so a wrong resolution is a compile error naming the
member rather than a value that happens to agree. The two unit columns are what
a "last declaration wins everywhere" fix would fail. `SizeOf(b)` = 4 is the
fourth column and is not a default anything. Positive control: the pinned binary
fails it with this ticket's own error. FPC 3.2.2 prints `42 11 33 4`.

This is the test the ticket asked for — it notes that
`test_generic_shadow_decl.pas` deliberately gives both records the SAME member
name so its result cannot depend on which template wins, and that a test
asserting the shadowing SEMANTICS belongs here.
