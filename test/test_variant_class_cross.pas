{ A Variant that holds a CLASS, and the unbox back to a scalar — the two halves
  had target-specific gaps that hid each other:

    - storing a class into a variant was implemented only on x86-64, so
      `a := b` failed to build on i386/aarch64 with "Variant :=: this scalar
      type not yet supported" (bug-a-variant-class-boxing-missing-on-i386-aarch64);
    - unboxing a variant to a scalar calls VariantToInt64, and the builtin unit
      holding it was pulled only as a side effect of some other feature, so
      `out_ := a` failed to build on every cross target
      (bug-a-variant-unbox-wrong-on-32bit-and-unavailable-cross).

  Both are per-target, so the value of this test is that all targets print the
  SAME line. Keep it building for i386/aarch64/arm32 as well as x86-64. }
program test_variant_class_cross;
type
  TBox = class
    V: Integer;
  end;
var a: Variant; b: TBox; i, out_: Integer; s: AnsiString;
begin
  b := TBox.Create;
  b.V := 7;
  { churn the slot through every payload kind, so each store arm runs and the
    clear-before-store path releases the previous one }
  for i := 1 to 100 do
  begin
    a := b;
    a := 'str';
    a := 3.5;
    a := i;
  end;
  s := 'end';
  out_ := a;
  writeln(s, ' ', b.V, ' ', out_);
end.
