program test_promoint_variant_32bit_heap_band;
{ RUN ON riscv32 (test-riscv32, via tools/run_target.sh). A green on x86-64
  does NOT cover this file's subject.

  A PromoInt's inline tier is ONE NATIVE WORD: PXXPromoFromInt spills to the
  heap tier outside +-2^31 when SizeOf(NativeInt) < 8 (promocore.pas). So the
  band 2^31..2^63 is INLINE on x86-64 and HEAP on every 32-bit target, and a
  heap promo boxes into a Variant as VT_PROMO_INT64 rather than VT_INT64. That
  path -- promo <-> Variant for a value that fits an Int64 but not a native
  word -- is reachable only on a 32-bit target, which is exactly the ESP32
  (xtensa and riscv32). Every expected line is CPython's answer for the same
  value; the band, not the arithmetic, is the subject.
  feature-a-promoint-variant-esp-targets }
var a, c: PromoInt;
    vv, ww: Variant;
    i: Integer;
    arr: array[0..2] of Variant;
begin
  { 2^40: heap tier on 32-bit only }
  a := 1;
  for i := 1 to 40 do a := a * 2;
  vv := a;
  Writeln(vv);
  c := vv;
  Writeln(c);
  ww := 3;
  Writeln(vv + ww);
  Writeln(vv * ww);
  if vv > ww then Writeln('mid-gt');
  { the negative side of the band }
  a := -a;
  vv := a;
  Writeln(vv);
  c := vv;
  Writeln(c);
  { past 64 bits, heap everywhere, held in an array of Variant beside a small int }
  a := 1;
  for i := 1 to 70 do a := a * 2;
  arr[0] := a;
  arr[1] := 7;
  arr[2] := a * a;
  for i := 0 to 2 do Writeln(arr[i]);
  c := arr[2];
  Writeln(c div a);
  { the edge: 2^31-1 is the last inline value on 32-bit, 2^31 the first spilled }
  a := 2147483647;
  vv := a;
  Writeln(vv);
  a := a + 1;
  vv := a;
  Writeln(vv);
  c := vv;
  Writeln(c - 1);
end.
