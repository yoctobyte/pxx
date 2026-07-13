---
prio: 55
---

# Advanced records: methods (and `public`/`private`) inside a record

- **Type:** feature (Pascal frontend)
- **Track:** P — Pascal frontend (shared `parser.inc`, so Track A file-lane)
- **Status:** working

## What is missing
A record with methods does not parse at all:

```pascal
type
  TPt = record
    X, Y: Longint;
    procedure Init(ax, ay: Longint);     { Expected: :, but got: procedure }
    function Sum: Longint;
  end;
```
Nor do visibility sections or constructors inside a record (`public`, `constructor
Create(...)`).

This is FPC's `{$modeswitch advancedrecords}`, which the RTL itself leans on: `TPoint`,
`TSize`, `TRect` in `rtl/inc/typshrdh.inc` are all advanced records with constructors and
operators, and `types.pp` re-exports them. So today those declarations only partly land.

## Why it matters beyond syntax
It is the standing lead on [[bug-pascal-unknown-type-silently-integer]]: with the
unknown-type fallback turned into an error, the fgl chain fails with `unknown type:
TPoint`, and `typshrdh.inc`'s TPoint is exactly one of these advanced records (methods,
`public`, and a self-referencing `constructor Create(apt: TPoint)`). How much of that
declaration currently lands is the first thing to check there.

## Shape
A record method is an ordinary method whose implicit `Self` is the RECORD, passed BY
REFERENCE (records are carried by address in this IR already, so this is the natural
lowering — no value-copy semantics to invent). Concretely:
- parse `procedure` / `function` / `constructor` / visibility inside `ParseRecordFields`,
  reusing the class-body member parser rather than growing a second one;
- register each as a proc named `TRec.Method` with `Self: <record>` injected at param 0
  by-ref — the same shift the class path does (mind the default-parameter arrays: they
  must shift WITH the params, see bug-pascal-method-default-param-self-shift);
- no VMT: records have no inheritance, so every call is static. That makes this a lot
  smaller than the class-method path.
- a record `constructor` is just a static function returning the record, FPC-style.

Operators (`class operator Add`) are a separate, later slice — do not fold them in.

## Gate
`make test` + self-host byte-identical + cross.

## Log
- 2026-07-13 — opened, found while chasing the unknown-type fallback (an advanced-record
  TPoint in FPC's own RTL was the thing that would not parse).


## Landed 2026-07-13

Methods inside a record now work: declaration, implementation, calls, mutation, and
record-valued results. Visibility sections (`public` / `private` / `strict private`) and
`class function`/`class procedure` inside a record are consumed too.

`Self` is the RECORD, passed **BY REFERENCE**. That is not a detail — the first attempt
passed it by value and `p.SetX` silently mutated a COPY, leaving the receiver unchanged. A
by-value Self loses every write.

No VMT: records have no inheritance, so every call is static, which is why this ended up far
smaller than the class-method path. The implementation side reuses ParseSubroutine unchanged
— FindUClass already finds record rows.

### The bug that actually cost the time
The implicit-Self field access hardcoded `Self` as `tyClass`. A record Self was therefore
dereferenced as an object POINTER, and the field access segfaulted. It now takes the
symbol's real type (`Syms[selfIdx].TypeKind`) — which is the correct thing for the class
path too, it was simply never exercised by anything but a class.

### Not included (deliberately)
`class operator` (Add / = / Explicit …) and record CONSTRUCTORS. Both are separate slices;
folding them in would have widened this well past a reviewable change. FPC's typshrdh.inc
uses both, so a full parse of it still needs them.

### Gate
`make test` green, `make lib-test` green, self-host byte-identical, `testmgr --tier full`
1215/1215 GREEN. Regression b268 pins the by-ref receiver (a by-value Self would silently
pass every other assertion).
