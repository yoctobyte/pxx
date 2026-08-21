---
track: P
prio: 60
type: bug
blocked-by: []
summary: "obj.Free through a base-class reference never runs the descendant's Destroy when the base declares no destructor — FPC runs it. Silent skipped cleanup / leak, not a diagnostic. The reserved root VMT slot 0 now makes the fix cheap."
status: backlog
---

# `Free` through a base reference skips the descendant's `Destroy`

Found while landing [[feature-a-tobject-root-method-vmt-slots]]; **pre-existing**
(reproduces on `pinned` too), so not a regression from that work.

## Repro

```pascal
program dtor3;
type
  TBase = class
    procedure Hello; virtual;
  end;
  TDer = class(TBase)
    destructor Destroy; override;
    procedure Hello; override;
  end;
procedure TBase.Hello; begin WriteLn('base'); end;
procedure TDer.Hello; begin WriteLn('der'); end;
destructor TDer.Destroy; begin WriteLn('TDer.Destroy'); end;
var b: TBase;
begin
  b := TDer.Create;
  b.Hello;        { 'der' — ordinary virtuals are fine }
  b.Free;
  WriteLn('done');
end.
```

| | output |
| --- | --- |
| FPC 3.2.2 | `der` / **`TDer.Destroy`** / `done` |
| pxx (HEAD and pinned) | `der` / `done` |

Same with `var o: TObject; o := TA.Create; o.Free;`.

## Cause

`GenMakeFreeObjectExpr` (`compiler/pasparser_stmt.inc:1426`) decides at PARSE
time whether to emit a `Destroy` call:

```pascal
if (ci >= 0) and (FindUMeth(ci, 'Destroy') >= 0) then
```

`ci` is the receiver's STATIC class. A base that declares no destructor has no
`Destroy` member, so nothing is emitted at all — the destructor is not "called
non-virtually", it is *absent*. Only the memory is freed. Every managed field the
descendant's `Destroy` was going to release stays released-never.

This is `normalise-dont-special-case` in miniature: destruction is dispatched by
a parse-time name lookup while every other virtual goes through the VMT.

## Fix

Now cheap, because slot `ROOT_VMT_DESTROY` (0) is reserved in every class:

1. give `TObject` a `Destroy` row bound to a no-op default body (a fourth
   `__pxxTObject*` in `compiler/builtin/builtin.pas`), and have
   `FillRootVMTSlotDefaults` (`pasparser_prog.inc`) stop skipping slot 0 so an
   unfilled slot points at that no-op instead of nil;
2. then the existing `FindUMeth(ci,'Destroy')` finds the row through the
   implicit-root tail and the call lowers to an ordinary VIRTUAL dispatch —
   which lands on the descendant's override.

Cost: one indirect call per `Free` on a class with no destructor (today: none).
Measure it before landing — `Free` is hot in the RTL containers.

Under `--compact-classes` there is no slot 0, so behaviour must stay exactly as
today (no diagnostic — an absent destructor is not an error, this is the low-memory
mode's documented limit).

## Gate

`make compiler/pascal26` + the repro above matching FPC, `tools/gate.sh quick`,
plus a `--compact-classes` row proving the compact path is unchanged. Add the
repro as `test/test_pascal_free_through_base_destroy.pas`.
