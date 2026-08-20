---
track: P
prio: 55
type: bug
blocked-by: []
summary: "An INLINE array type as a `class var` is `unknown type: array`. A NAMED one indexes correctly but carries no array metadata, so `Length(F)` answers 0 where FPC says 4 (silent, no diagnostic), `SizeOf(F)` and `SetLength` error, and `TC.F[0]` will not parse. The class-var branch is `ParseTypeKind` + `AllocVar` and has none of the var section's array machinery. Blocks the rtl-generics corpus climb at wall 18."
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

## Measured (self-hosted build at HEAD, FPC 3.2.2 as the oracle)

**Corrected 2026-08-20**, an hour after filing. The first version of this
ticket said a named array type "compiles silently as a scalar and fails at the
use site". That was inferred from two failing uses and it is wrong: the
ordinary uses work. Re-measured shape by shape, the real split is:

| `class var F: ...`, then the use | pxx | FPC |
| --- | --- | --- |
| `TA = array[0..3] of Integer`, `F[i] := ...` in a class method | **works** | works |
| ... `c.F[0]` through an instance | **works** | works |
| ... `array[TKind]` as the index (since the wall-18 fix) | **works** | works |
| ... `Length(F)` | **0** | 4 |
| ... `SizeOf(F)` | `SizeOf: unknown type or variable` | 16 |
| ... `TC.F[0]`, class-qualified | `unexpected token` (parse) | 5 |
| `TD = array of Integer`, `SetLength(G, 3)` | `SetLength expects a string variable in IR codegen` | works |
| `array[0..3] of Integer` inline | `unknown type: array` | works |
| `array of Integer` inline | `unknown type: array` | works |

**`Length(F)` answering 0 is the one silent wrong value here**, and it is the
reason this ticket keeps its priority: every other row stops the build. A loop
written `for i := 0 to Length(F) - 1` over a class-var array does nothing at
all and reports no error.

The declaration is therefore NOT silently a scalar — the alias is resolved well
enough for indexing to work. What is missing is the array METADATA on the
allocated symbol: `AllocVar` reserves a scalar slot, so `ArrLen` / `IsArray`
are never set, and every consumer that asks the symbol about its shape rather
than just indexing it (`Length`, `SizeOf`, `SetLength`, and the class-qualified
selector's parse) gets the wrong answer or no answer.

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
    class var F: TA;
  public
    class procedure Go;
  end;
class procedure TC.Go;
begin
  F[0] := 1;
  WriteLn(F[0]);        { 1 -- indexing is fine }
  WriteLn(Length(F));   { 0 in pxx, 4 in FPC -- SILENT }
end;
begin
  TC.Go;
end.
```

Swap `F: TA` for `F: array[0..3] of Integer` to see the honest arm
(`unknown type: array` at the declaration). FPC 3.2.2 accepts both.
