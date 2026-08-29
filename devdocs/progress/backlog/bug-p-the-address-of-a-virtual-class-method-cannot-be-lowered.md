---
prio: 55
track: P
owner: unassigned
---

# The address of a virtual class method cannot be lowered (`AN_CLASS_VIRTUAL_CALL`, kind 88)

- **Type:** bug (refused construct; the compiler correctly errors rather than
  miscompiling) — **Track P** (Pascal frontend lowering). **May escalate to
  Track A** if a new IR op is needed to name a vmt slot as a value — file it
  there if so rather than reaching into shared internals under P.
- **Found by:** rung 6, `rtl-generics`. Exposed *underneath*
  [[bug-p-a-generic-methods-out-of-line-header-binds-to-a-same-named-non-generic-class]]
  once that fix let `generics.defaults.pas` past line 2173; this is the wall at
  2351. Fifth distinct wall on that unit, and **not** typinfo.
- **Binary:** `e82c2f63a242`, verified fixedpoint at `042bcbb32`.

## Symptom

Taking the **address** of a virtual class method — using it as a value rather
than calling it — fails to lower:

```
error: IR_UNSUPPORTED: frontend could not lower AST node (kind 88)
       — a frontend gap, would miscompile
```

`AN_CLASS_VIRTUAL_CALL` (`defs.inc:512`) models "a virtual class method called
through a receiver". In this position it is not called at all, so nothing
lowers it. The error is honest — it refuses rather than emitting something
wrong — which is why this is a gap rather than a silent-miscompile escape.

## Repro (18 lines; FPC prints `TRUE`, pxx errors)

```pascal
program v2;
{$MODE DELPHI}{$H+}
type
  TMethod = record Code, Data: Pointer; end;   { or: uses SysUtils }
  TSel = function (A: LongInt): LongInt of object;
  TSvc = class
    class function Pick(A: LongInt): LongInt; virtual;
  end;
class function TSvc.Pick(A: LongInt): LongInt;
begin
  Result := A * 2;
end;
var
  p: Pointer;
begin
  p := TMethod(TSel(TSvc.Pick)).Code;   // <-- IR_UNSUPPORTED (kind 88)
  WriteLn(PtrUInt(p) <> 0);
end.
```

**Not generic-specific.** The corpus site is inside a generic, but the repro
above has no generics at all — worth stating because the rung-6 context makes it
look like a generics bug and it is not. `TMethod` is present in
`lib/rtl/sysutils.pas:133`; the repro declares it inline only to stay
dependency-free.

## Corpus site

```pascal
FEqualityComparerInstances[tkFile] :=
  TInstance.CreateSelector(TMethod(TSelectMethod(
    THashService<T>.SelectBinaryEqualityComparer)).Code);
```

One of a table of ~20 such initialisers, so it gates the comparer dispatch table
rather than a single line.

## Note on the wall count

Rung 6 was reported as four walls with the claim "complete set for this unit".
That claim was hedged for exactly this reason — code behind a stub is
type-checked against the stub, so clearing one wall can expose another. This is
the first instance. Update the count in [[feature-pascal-corpus-expansion]]
rather than treating the earlier partition as wrong: it listed what must be
built, not a prediction of first-try success.
