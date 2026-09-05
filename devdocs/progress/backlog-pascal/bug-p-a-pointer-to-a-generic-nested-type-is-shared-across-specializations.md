---
slug: bug-p-a-pointer-to-a-generic-nested-type-is-shared-across-specializations
title: "A pointer to a generic class's nested type keeps the FIRST specialization's pointee"
track: P
prio: 45
type: bug
blocked-by: []
status: backlog
owner: ""
created: 2026-09-05
summary: "`generic TBox<_T>` declaring `type PCell = ^TCell; TCell = record d: _T; end;` and specialized twice compiles the second specialization\'s `n^.d := v` against the FIRST one\'s element type: `cannot assign AnsiString to Integer`, and the message flips direction if the specializations are declared the other way round. The nested RECORD is specialized correctly; only the POINTER\'s pointee is shared. Pre-existing on pin v403, fpc 3.2.2 accepts both orders."
---

# Repro

```pascal
{$mode objfpc}
program v1;
type
  generic TBox<_T> = class(TObject)
    type PCell = ^TCell; TCell = record d: _T; end;
    var head: PCell;
    procedure Put(v: _T);
  end;
procedure TBox.Put(v: _T); var n: PCell; begin new(n); n^.d := v; head := n; end;
type
  TIntBox = specialize TBox<Integer>;
  TStrBox = specialize TBox<AnsiString>;
var i: TIntBox; s: TStrBox;
begin
  i := TIntBox.Create; s := TStrBox.Create;
  i.Put(7); s.Put('hi');
  WriteLn(i.head^.d,' ',s.head^.d);
end.
```

`pascal26:0: error: incompatible types: cannot assign AnsiString to Integer`

fpc 3.2.2 compiles it and prints `7 hi`. Pin v403 gives the same error, so this
is pre-existing.

# It is ORDER-DEPENDENT, which is what names the mechanism

Swap the two `specialize` lines and the message swaps with them:

| declared first | error |
| --- | --- |
| `TBox<Integer>` | cannot assign **AnsiString to Integer** |
| `TBox<AnsiString>` | cannot assign **Integer to AnsiString** |

The pointee is whatever the FIRST specialization made it. That is a value read
from a shared slot, not from the type.

# Three-way control — the trigger is a CONJUNCTION

| probe | shape | result |
| --- | --- | --- |
| v1 | pointer to nested type, **two** specializations | **refused** |
| v2 | pointer to nested type, **one** specialization | compiles, correct |
| v3 | nested record used **directly**, two specializations | compiles, correct (`7 hi`) |

So it is **not** "pointers to nested types are broken" (v2) and **not** "nested
types are not specialized" (v3 — the record IS specialized per instantiation).
It is specifically the pointer's POINTEE resolution being done once and reused.
A fix aimed at either half alone will pass its own probe and leave this failing.

The self-reference in the original (`next: PCell` inside `TCell`) is NOT
required — v1 has no self-reference.

# Where it is NOT

`pasparser_generic.inc`'s nested-type HOISTING is a different path and does not
fire here: hoisting is triggered only when a nested type is used as a GENERIC
ARGUMENT, and `PCell = ^TCell` uses it as a pointee. Its header comment says so
("ONLY WHAT IS ACTUALLY USED AS A GENERIC ARGUMENT IS HOISTED"). Do not start
there.

# Why it matters beyond the two rows

This is the canonical linked-list generic — a nested node record plus a pointer
to it is how you write `TList<T>` in Object Pascal without dynamic arrays. Any
program specializing such a container twice in one compilation gets a compile
error whose text names neither the template nor the specialization.

Also: the diagnostic carries **line 0**, i.e. no location at all, which is its
own small defect — the message cannot be traced to a line by anyone reading it.

# Corpus rows

`tgeneric6.pp` and `tgeneric8.pp` of the FPC test suite, both blocked on exactly
this after the header-lexing fix (`9a3b8f38c`) let the parser reach the bodies.
They are the two-row shape noted in [[feature-pascal-corpus-fpc-testsuite]].

# Gate

Both orders of the repro compiling and printing `7 hi`, v2 and v3 unchanged,
plus tgeneric6/tgeneric8 diffed against fpc OUTPUT rather than scored on an exit
code, plus `make test` and the self-host fixedpoint.
