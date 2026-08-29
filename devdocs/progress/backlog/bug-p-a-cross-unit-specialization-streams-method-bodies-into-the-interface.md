---
slug: bug-p-a-cross-unit-specialization-streams-method-bodies-into-the-interface
track: P
prio: 65
type: bug
status: backlog
blocked-by: []
summary: "A unit that specializes another unit's generic IN ITS INTERFACE gets the template's method bodies streamed into the interface section, where a method implementation is not a declaration: `unexpected token in a unit interface section` pointing at the TEMPLATE's file. Pre-existing on pinned, objfpc binder form, no Delphi surface involved — the same-file and the program-level cases both work, and a template with only FIELDS works cross-unit too. This is the next wall for `uses Generics.Collections`, because real templates have methods. Named as tgeneric91 in test/test_generic_spec_per_unit.pas's own header but never ticketed."
owner: unassigned
---

# A cross-unit specialization streams method bodies into the interface section

Found while fixing
[[bug-p-a-delphi-mode-generic-from-a-used-unit-cannot-be-specialized]] — the
first draft of that ticket's test gave its templates constructors and hit this
instead. It is **not** that bug, shares no mechanism with it, and reproduces on
`pinned` with no Delphi surface anywhere.

## Repro — three files, FPC prints `7`

```pascal
unit ugm;                       unit ugu;                              program pgm;
{$MODE OBJFPC}                  {$MODE OBJFPC}                         {$MODE OBJFPC}
interface                       interface                              uses ugu;
type                            uses ugm;                              begin
  generic TSk<T> = class        type TSkI = specialize TSk<LongInt>;      WriteLn(MidVal);
    Val: Integer;               function MidVal: Integer;              end.
    constructor Create(v: Integer);  implementation
  end;                          function MidVal: Integer;
implementation                  var s: TSkI;
constructor TSk.Create(v: Integer);  begin s := TSkI.Create(7); Result := s.Val; end;
begin Val := v; end;            end.
end.
```

```
pascal26:10: error: unexpected token in a unit interface section: it starts no declaration (a mistyped section header?)
  in: ugm.pas
  near:  Integer   end  >>> constructor TSkI
```

Note where the error points: **`ugm.pas`, the file that declares the
template**, at the line of the constructor's implementation. The streamed
tokens carry the template's source offsets, so the diagnostic names a file
whose text is fine and a line the user did not ask to be compiled here.

## The boundary — four cases, three of them work

| where the specialization is written | template has | pxx | fpc |
| --- | --- | --- | --- |
| the main program's declaration part | methods | OK | OK |
| the same unit as the template | methods | OK | OK |
| a **using unit's interface** | **methods** | **the error above** | OK |
| a using unit's interface | fields only | OK | OK |

The last row is what makes this specific: the specialization DECLARATION
crosses units fine (that is what
`test/test_generic_spec_per_unit.pas` covers, and its header says so in as
many words — *"A plain field keeps this about the specialization DECLARATION;
cross-unit generic METHOD bodies are their own gap (tgeneric91)"*). What
crosses badly is the **materialisation of the methods**.

## Where to look

`SpecializeStream` splices the concrete class and then its method bodies as
ordinary declarations at the current position. Inside a unit INTERFACE that is
illegal Pascal: an interface holds signatures, and the bodies belong in the
implementation section. `PendingSpecTi` / `PendingSpecIdx` already exist for
exactly this shape one level down — *"specializations seen in the current type
section whose template methods must be materialised AFTER the section closes
(streaming a method inside the section would terminate it)"*, flushed by
`ParseTypeSection` — so the machinery for deferring a materialisation past a
section boundary is present and this is a second, larger boundary it does not
yet know about. **That is a direction, not a diagnosis: it has not been
measured.**

## Why it matters now

`uses Generics.Collections` is the corpus goal of
[[feature-pascal-corpus-expansion]], and `generics.collections.pas`
specializes `Generics.Defaults`' comparers in its interface. Those templates
have methods — that is the entire point of a comparer. So this is the wall
behind the one just cleared, and a fix for it is worth more than its own repro
suggests.

## Gate

The three-file repro printing `7`; `test_generic_spec_per_unit` still 4/4; the
Delphi cross-unit tests still green with their templates given methods back;
the per-fix loop.
