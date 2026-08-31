{ A `var` parameter of every scalar kind, read AND written through IR_LEA, plus
  the forwarding shape that is the whole point: `Outer(var q)` handing q to
  `Inner(var p)`. On the 32-bit backends the parameter SLOT holds the caller's
  address, so IR_LEA must deref it — without that, the inner write lands on the
  local slot and never reaches the caller.

  Why it is a CROSS test and not a native one. `ABIParamSlotHoldsValueAddr`
  (abi.inc) exists so all six backends answer "does this slot hold an address?"
  identically, and riscv32 and xtensa each carried a hand-rolled arm AHEAD of
  the call to it — `skParam and IsRef and not IsArray and TypeKind <>
  tyAnsiString` — which is a strict subset of the predicate's own `IsRef`
  clause, reaching the same single-word load. Deleted 2026-08-31 with every
  binary here byte-identical across the change.

  This file is what made that measurable, so it stays: it is the population the
  deletion had to be safe for. Positive control, run at the time — disabling the
  ABIParamSlotHoldsValueAddr arm instead prints `x=5` and `a2=0` and then
  segfaults on the Double, so these rows do reach the chain rather than passing
  vacuously. }
program test_cross_var_param_scalar_kinds;
{$mode objfpc}{$H+}
type TI = array[0..3] of Integer;

procedure Inner(var p: Integer); begin p := p + 1; end;
procedure Outer(var q: Integer); begin Inner(q); end;   { var -> var forwarding }
procedure W(var r: TI); begin r[2] := 77; end;          { by-ref fixed array }
procedure S1(var s: AnsiString); begin s := s + '!'; end;
procedure V(var d: Double); begin d := d * 2; end;
procedure I64(var n: Int64); begin n := n + 1; end;
procedure B(var f: Boolean); begin f := not f; end;
procedure C(var ch: Char); begin ch := 'Z'; end;

var
  x: Integer; a: TI; st: AnsiString; dd: Double; nn: Int64;
  bb: Boolean; cc: Char; p: ^Integer;
begin
  x := 5;      Outer(x);  WriteLn('x=', x);
  a[2] := 0;   W(a);      WriteLn('a2=', a[2]);
  st := 'hi';  S1(st);    WriteLn('st=', st);
  dd := 1.5;   V(dd);     WriteLn('dd=', dd:0:2);
  nn := 41;    I64(nn);   WriteLn('nn=', nn);
  bb := False; B(bb);     WriteLn('bb=', bb);
  cc := 'a';   C(cc);     WriteLn('cc=', cc);
  p := @x;                WriteLn('p=', p^);
end.
