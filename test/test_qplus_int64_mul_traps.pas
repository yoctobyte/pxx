{ SPDX-License-Identifier: Zlib }
program QPlusInt64MulTraps;
{ {$Q+} must TRAP a 64x64 multiply whose product does not fit, on every target.
  x86-64 always did. The four 32-bit backends printed the wrapped value
  (-2446744073709551616 for row 0) and carried on, because detecting it needs
  the high half of a 128-bit product, which they did not build (the unsigned
  half only on riscv32, neither half on xtensa).
  bug-a-64-bit-multiply-overflow-is-unchecked-under-q-plus-on-riscv32-and-xtensa

  One shape per run, chosen by ARGUMENT COUNT, because a trap ends the run:
    0 args  signed, positive overflow         must trap (exit 215)
    1 arg   signed, negative overflow         must trap
    2 args  -1 * Low(Int64)                   must trap (division cannot test it)
    3 args  unsigned overflow                 must trap
    4 args  the CONTROLS: products that fit, including exactly Low(Int64) and
            the largest square. Must NOT trap, and must print the exact values.
    5 args  the DEFAULT, {$Q-}: the same overflowing products WRAP and do not
            trap. The check is opt-in; the default path gets no helper call.
  A fix that traps unconditionally passes rows 0-3; rows 4 and 5 are what fail it. }
{$Q-}
procedure DefaultWraps;
var a, b, c: Int64; p, q, r: QWord;
begin
  a := 4000000000000000000; b := 4; c := a * b; WriteLn('wrapped ', c);
  p := QWord(1) shl 40; q := QWord(1) shl 30; r := p * q; WriteLn('wrapped ', r);
end;
{$Q+}
var x, y, z: Int64; u, v, w: QWord;
begin
  case ParamCount of
    0: begin x := 4000000000000000000; y := 4; z := x * y; WriteLn('WRAPPED ', z); end;
    1: begin x := -4000000000000000000; y := 3; z := x * y; WriteLn('WRAPPED ', z); end;
    2: begin x := -1; y := -9223372036854775807 - 1; z := x * y; WriteLn('WRAPPED ', z); end;
    3: begin u := QWord(1) shl 40; v := QWord(1) shl 30; w := u * v; WriteLn('WRAPPED ', w); end;
    5: DefaultWraps;
  else
    begin
      x := -4; y := 2305843009213693952; z := x * y; WriteLn('low ', z);
      x := 3037000499; y := 3037000499; z := x * y; WriteLn('square ', z);
      x := -1; y := 9223372036854775807; z := x * y; WriteLn('neg ', z);
      x := 123456789; y := -987654321; z := x * y; WriteLn('mixed ', z);
      u := QWord(1) shl 40; v := QWord(1) shl 20; w := u * v; WriteLn('unsigned ', w);
      x := 0; y := -9223372036854775807 - 1; z := x * y; WriteLn('zero ', z);
    end;
  end;
end.
