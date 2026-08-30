---
slug: bug-p-a-cross-unit-specialization-streams-method-bodies-into-the-interface
track: P
prio: 65
type: bug
status: working
blocked-by: []
summary: "A unit that specializes another unit's generic IN ITS INTERFACE gets the template's method bodies streamed into the interface section, where a method implementation is not a declaration: `unexpected token in a unit interface section` pointing at the TEMPLATE's file. Pre-existing on pinned, objfpc binder form, no Delphi surface involved — the same-file and the program-level cases both work, and a template with only FIELDS works cross-unit too. This is the next wall for `uses Generics.Collections`, because real templates have methods. Named as tgeneric91 in test/test_generic_spec_per_unit.pas's own header but never ticketed."
owner: frankR
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

## 2026-08-30 (frankR) — fixed; and the ticket's "where to look" was right

Reproduced exactly. Then finished drawing the boundary the ticket had half-drawn
— one row it did not have turned out to be the one that explains the whole thing.

| specialization written in | template has | before | after |
| --- | --- | --- | --- |
| the main program's declaration part | methods | OK | OK |
| the **same unit** as the template (interface) | methods | OK | OK |
| a using unit's **implementation** | methods | **OK** | OK |
| a using unit's **interface** | methods | **the error** | **OK** |
| a using unit's interface | fields only | OK | OK |

The third row is the new one: a specialization in the using unit's
IMPLEMENTATION is fine. So this is not "cross-unit" — it is **the interface
section specifically**, and only when the template has methods.

### Why same-unit worked and cross-unit did not

The pend is gated on `GenericMethodCount > 0` (`ParseSpecialization`):

```pascal
  if GenericMethodCount > 0 then
  begin
    PendingSpecTi[PendingSpecCount] := ti; ...
```

- **Template in THIS unit** — its method bodies live in this unit's
  implementation and are still unparsed while the interface is being read, so
  `GenericMethodCount` is 0, nothing is pended, and `BufferGenericMethod`
  materialises them later *from the implementation*, once it holds both halves.
  Its own comment says so: *"Only specializations already registered are
  streamed here; ones declared later stream this method from
  ParseSpecialization."*
- **Template from a USED unit** — already fully parsed, so its methods are
  buffered, the pend fires, and `FlushPendingClassSpecializations` runs at the
  end of the interface's type section and splices bodies **into the interface**.
- **Fields only** — nothing to splice either way.

So the two materialisation paths partition by ordering, and the cross-unit case
is the only one that lands on the wrong side of the partition while inside an
interface. The ticket's "where to look" was correct, and the `GenericMethodCount`
gate is the missing half of the explanation.

### Fix — `pasparser_generic.inc` only

`SpecializeStream` splices at the parse cursor, which is exactly wrong here.
Split into `SpecializeStreamAt(..., at)` returning the token count inserted, with
`SpecializeStream` as the `at := TokPos` wrapper so all five existing callers are
untouched. `FlushPendingClassSpecializations` then, **when `InInterface`**,
splices at `UnitImplAnchor` instead: just past the unit's `implementation`, and
past its `uses` clause if it has one.

Two details that are not incidental:

- **`implementation` is a plain `tkIdent`, not a keyword token.** `ParseUnit`
  scans for it by name (`pasparser_proc.inc`), and `UnitImplAnchor` matches that
  scan deliberately — two different notions of where the section starts would be
  a drift bug waiting.
- **The `uses` skip is load-bearing.** `implementation uses ugm;` is the ordinary
  spelling of an impl-private import, and a body spliced in front of it leaves a
  `uses` that is no longer first in its section. Tested.
- **The anchor advances by each splice's return.** Two specializations in one
  interface would otherwise each land in front of the previous one, reversing
  them. Tested with two.

### Verified — all six rows compile AND run

Every row of the table above prints `7`. Plus:

- `implementation` opening with `uses`, and **two** specializations of the same
  template in one interface → prints `109` (7 + 2 + 100), so ordering and the
  uses-skip both hold;
- `test_generic_spec_per_unit` — **4 / 4** (the ticket's named gate);
- `test_delphi_generic_cross_unit` — **4 / 4** (Delphi cross-unit, templates
  with methods, still green);
- `test_generic_cross_unit_inline_specialize` — **1 / 1**.

Gate: `make compiler/pascal26` converged, `d5a35c8de13a`.

### Where the wall moves next

`uses Generics.Collections` is the reason this mattered — `generics.collections`
specializes `Generics.Defaults`' comparers in its interface and those templates
have methods. Re-measured after the fix; recorded below.
