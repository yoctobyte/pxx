---
track: P
prio: 60
type: bug
blocked-by: []
summary: "obj.Free through a base-class reference never runs the descendant's Destroy when the base declares no destructor — FPC runs it. Silent skipped cleanup / leak, not a diagnostic. The reserved root VMT slot 0 now makes the fix cheap."
status: done
owner: claude-A
commit: PENDING-COMMIT
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

## What was done

The ticket's plan, with one change of address. It said to put the empty default
body in `compiler/builtin/builtin.pas` beside the other three `__pxxTObject*`
routines. Measured first: pulling that unit costs **~43 KB** of code (a small
class program goes 60,782 -> 103,636 bytes), and the pull is name-triggered by
`.Equals` / `.GetHashCode` / `.ToString`, so triggering it on `.Free` would have
put 43 KB into essentially every class-bearing program, cross and embedded
targets included.

`__pxxTObjectDestroy` went into **`builtinheap.pas`** instead, which `tkClass`
already pulls into every class program (`DetectPascalRuntimeNeeds`). Measured
cost of the whole change on that same program: **93 bytes** of code, one extra
proc.

Registration is separate from the other three rows on purpose: their bodies live
in `builtin` and Destroy's in `builtinheap`, so a program can have one unit and
not the other — sharing `EnsureTObjectRootMethods`' `FindUMeth(ci, 'Equals')`
idempotency guard would have made Destroy's row depend on whether the program
happened to mention `ToString`.

## The cost, measured

The ticket asked for this before landing. 20,000,000 iterations of
`Create; assign; read; Free` on a destructor-less class, `-O2`, three runs each,
same box:

| | run 1 | run 2 | run 3 |
| --- | --- | --- | --- |
| before (`pinned`) | 2.14 s | 2.13 s | 2.13 s |
| after | 2.34 s | 2.25 s | 2.23 s |

~5% on a loop whose entire body is Create/Free — about 5 ns per Free, the
indirect call. Nothing else in that loop does any work, so this is the ceiling,
not a typical cost.

Leak check: 200,000 iterations over a class with a `string` and a dyn-array
field (no destructor) plus one with a destructor — RSS 392 KB before and after,
identical. `PXXClassFinalize` still runs after the whole Destroy chain, which is
FPC's `FreeInstance` timing.

## Verified against fpc

`test/test_pascal_free_through_base_destroy.pas`, byte-identical to
`fpc -Mobjfpc -O1`: the bug's own shape (a `TBase` reference), a static
`TObject` reference, a reference to the MIDDLE class which does declare a
destructor (the chain must start at TDer and not run twice), the exact class,
a class with no destructor anywhere (the empty default body runs and prints
nothing — the row that proves slot 0 is never nil), a bare `TMid`, and `Free` on
nil.

`--compact-classes` asserted separately in the Makefile with its OWN expected
output: no root slots there, so rows `--1` and `--2` keep today's behaviour and
print no destructor line. That is the low-memory mode's documented limit, not a
regression.

## Gate

`make compiler/pascal26` (self-host fixedpoint) + `tools/gate.sh quick` GREEN.

## Log
- 2026-08-22 — resolved, commit PENDING-COMMIT.
