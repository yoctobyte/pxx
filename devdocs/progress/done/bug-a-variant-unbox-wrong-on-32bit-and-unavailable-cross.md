---
track: A
prio: 70
type: bug
---

# Variant -> scalar unbox is unavailable on cross targets

Found 2026-07-28 while cross-checking the new class-into-variant boxing
([[bug-a-variant-class-boxing-missing-on-i386-aarch64]]).

Assigning a Variant to a scalar fails to BUILD for i386, aarch64 and arm32:

```pascal
program crossvar;
type
  TBox = class
    V: Integer;
  end;
var a: Variant; b: TBox; i, out_: Integer; s: AnsiString;
begin
  b := TBox.Create;
  b.V := 7;
  for i := 1 to 100 do
  begin
    a := b;
    a := 'str';
    a := 3.5;
    a := i;
  end;
  s := 'end';
  out_ := a;                 { unbox the Integer 100 }
  writeln(s, ' ', b.V, ' ', out_);
end.
```

x86-64 prints `end 7 100`. Every cross target stops at the unbox:

```
error: variant unbox: VariantToInt64 builtin not loaded
```

Also with `o64: Int64` (`o64 := a`) and on a program with no class at all —
the unbox is what fails, not the boxing.

## Cause

`IRLowerVariantAsScalar` (`ir.inc:~3835`) lowers the unbox to a call to
`VariantToInt64` / `VariantToDouble` / `VariantToBool` / `VariantToChar` /
`VariantToStr`, and `Error`s when `FindProc` cannot see one. Those live in
`compiler/builtin/builtin.pas`, which is pulled only when something ELSE in the
program needs it — so whether a given source builds for a cross target is
decided by an unrelated declaration elsewhere in the file. On x86-64 the unit is
effectively always present, which is why this never showed natively.

So the fix is about ENSURING the builtin unit is loaded when a variant unbox is
lowered (the same "Enable*Runtime" pre-scan shape other runtime helpers use),
not about the backends' codegen.

## Correctness note — measured, NOT assumed

An earlier draft of this ticket claimed the unbox returns wrong values on
i386/arm32 (addresses) and `1` on aarch64. **That was a harness error, not a
compiler defect**: the check ran `pxx ... | tail -1 >/dev/null && run_target`,
whose pipeline exit status hides a failed compile, so `run_target` executed a
STALE binary left from an earlier edit of the source. With the compile status
actually checked, all three targets fail to build and nothing wrong is computed.
No silent-wrong-value claim survives.

(Lesson worth keeping: never gate a run on `compile | tail -N >/dev/null` — the
pipeline's status is `tail`'s.)

## Gate

`make test` + cross for i386 / aarch64 / arm32 with the program above, whose
output must match x86-64's on every target.

## Log
- 2026-07-28 — resolved, commit HEAD.

## Fix

The program-level pre-scan in `parser.inc` now sets `needsBuiltin` when the
token `variant` appears anywhere, with the same ESP/xtensa exclusions the
Str/Val pull uses — so the unit holding VariantToInt64 and friends is present
wherever a variant can be unboxed, instead of arriving as a side effect of an
unrelated declaration.

All four targets now print `end 7 100` for the program above.
`test/test_variant_class_cross.pas` is registered in `test-i386`,
`test-aarch64` and `test-arm32`, asserting the identical line on each.
