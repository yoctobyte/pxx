---
track: P
prio: 55
type: bug
blocked-by: []
summary: "`class var F: array[0..3] of Integer` is `unknown type: array`, and — the dangerous arm — `class var F: TA` where `TA = array[0..3] of Integer` COMPILES SILENTLY AS A SCALAR and fails somewhere else at the use site. The class-var branch parses only `ParseTypeKind` + `AllocVar`; it has none of the var section's array machinery. Blocks the rtl-generics corpus climb at wall 18."
---

# A `class var` takes no array type, and a named array type is silently a scalar

- **Type:** bug (Pascal frontend) — **Track P**.
- **Filed:** 2026-08-20 by frank3, from wall 18 of
  [[feature-pascal-corpus-generics]]. Filed as its own queue entry rather than
  left banked in that ticket, because `working/` and `unfinished/` are
  invisible to `ready`/`next` and a finding parked there does not get picked
  up — which is exactly how this rung's own ticket went unseen for weeks.
- **Shared-file catch:** the fix is in the SHARED `compiler/parser.inc`, which
  Track P and Track A both touch. Obey A's gate and the no-concurrent-edit
  rule.

## Measured (self-hosted build at `57b9b7148`)

| `class var F: ...` | today |
| --- | --- |
| `array[0..3] of Integer` (inline fixed) | `unknown type: array` |
| `array of Integer` (inline dynamic) | `unknown type: array` |
| `TA`, where `TA = array[0..3] of Integer` | **compiles as a scalar**, fails later at the use site |
| `TD`, where `TD = array of Integer` | **compiles as a scalar**, fails later at the use site |

The bottom two are why this is rated above the two that error. An error arm at
least stops; a wrong TYPE accepted silently puts the diagnostic somewhere else
entirely, and the reader has no reason to suspect the declaration.

Ordinary instance fields are fine — `array[0..3]`, `array of T`, and (since
`57b9b7148`) an ordinal type as the index all work in a record or class field.
It is specifically the `class var` section.

## Cause

`compiler/parser.inc` ~27726, the `class var` branch, is:

```pascal
Expect(tkColon, ':');
fTk := ParseTypeKind; fRec := LastTypeRecId;
...
i := AllocVar('', fTk);
```

`ParseTypeKind` has no array case, so `array` reaches the unknown-type error;
a named array alias resolves to something `ParseTypeKind` will answer with, and
`AllocVar` then reserves a scalar slot. Storage is an anonymous global
(`CurProc < 0`), which is not the problem — the problem is that nothing on this
path ever calls `AllocArray` / `AllocDynArray`.

## Do NOT microfix this

`ParseVarSection` (`:24622`) already has all of it: the `isArr` / `isDyn` /
`arrLo` / `arrHi` / `ndCnt` descriptor, `FindArrayType` for the named-alias
case, the `packed` and nested-dimension handling, and the alloc loop at
~24925-24990 that turns the descriptor into `AllocArray` / `AllocDynArray` with
the element record id, `SymArrNDims`, the dyn-element row shape and the proc
signature threaded through. Copying a slice of that into the class-var branch
makes a **fifth** copy of array-declaration parsing in this file. Wall 18 was
exactly that failure: four inline copies of the array-BOUND parser, one of
which stayed broken after the other three were fixed, and only a test caught
it (`devdocs/dev/normalise-dont-special-case.md`).

The shape the fix wants, per `devdocs/dev/root-cause-over-microfix.md`:

1. Extract the type-parsing prologue of `ParseVarSection` into a routine that
   fills a **descriptor record** and consumes no storage decisions.
2. Extract the alloc loop into "allocate one symbol from this descriptor".
3. `ParseVarSection` becomes those two; the `class var` branch becomes step 1
   plus step 2 with the class-var registration in between; the record-field and
   class-field paths are the next candidates to fold in, which is where the
   quadruple bound-parser came from in the first place.

Expect this to be a session of its own. It should close this ticket, make wall
18 fall, and plausibly retire several of the inline copies at once — measure it
in tickets-closed-per-change, not lines touched.

## Repro

```pascal
program cv;
{$mode objfpc}{$H+}
type
  TA = array[0..3] of Integer;
  TC = class
  private
    class var F: TA;        { compiles; F is a scalar }
  public
    class procedure Go;
  end;
class procedure TC.Go;
begin
  F[0] := 1;                { the error lands HERE, not at the declaration }
  WriteLn(F[0]);
end;
begin
  TC.Go;
end.
```

Swap `F: TA` for `F: array[0..3] of Integer` to see the honest arm
(`unknown type: array`). FPC 3.2.2 accepts both.
