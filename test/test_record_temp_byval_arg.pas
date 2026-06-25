program test_record_temp_byval_arg;
{ Regression: a record function-result TEMPORARY passed as a by-value record
  argument must lower in the aarch64/arm32 backends (was: "load through pointer
  of this type not yet supported"). A small (<=4-byte) record on arm32, <=8-byte
  on aarch64/x86-64. bug-aarch64-arm32-record-temp-byvalue-arg. }
type R = record a, b, c, d: Byte end;     { 4 bytes }
function Mk(v: Byte): R;
begin Mk.a := v; Mk.b := v + 1; Mk.c := v + 2; Mk.d := v + 3; end;
function Sum(x: R): Integer;
begin Sum := x.a + x.b + x.c + x.d; end;
var n: Integer; r: R;
begin
  n := Sum(Mk(3));        { temporary by-value arg }
  writeln(n);              { 3+4+5+6 = 18 }
  r := Mk(10);
  n := Sum(r);            { named (regression guard) }
  writeln(n);              { 10+11+12+13 = 46 }
end.
