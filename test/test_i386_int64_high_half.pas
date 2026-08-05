program test_i386_int64_high_half;
{ Regression: on i386 an Int64 value whose PRODUCER is still 32-bit must be
  widened before anything consumes edx:eax. Three sites assumed "the node's type
  says 64-bit, therefore edx:eax already holds it" and read whatever the previous
  code left in edx:

    IR_WRITE  64-bit branch  -- writeln(<inlined Int64 fn>(e))
    IR_NEG    64-bit branch  -- Abs(e) inlines to `if e<0 then -e else e`, Int64
    IR_NOT    64-bit branch  -- same shape

  Silent: the low half was always right, so output looked plausible, and the
  garbage moved as surrounding code changed. Only reachable at -O2/-O3, where
  the inliner collapses an Int64-returning helper down to a bare 32-bit load.
  IntToStr takes an Int64, so `IntToStr(Abs(n))` was silently wrong on i386 —
  which is how it was found (Format('%e') printing 3.333E--4294967295).
  bug-a-i386-int64-arg-high-half-uninitialized. }
procedure ShowI64(v: Int64); begin writeln(v); end;
function F64(v: Int64): Int64; begin F64 := v; end;
function T64(v: Int64): Int64; begin if v < 0 then T64 := -v else T64 := v; end;
var e: Integer; x: Int64;
begin
  e := -1;
  ShowI64(Abs(e));            { 1  — IR_NEG via the inlined Abs }
  writeln(F64(e));            { -1 — IR_WRITE over a 32-bit producer }
  writeln(T64(e));            { 1  — both }
  ShowI64(F64(e));            { -1 }
  ShowI64(T64(e));            { 1 }
  x := F64(Abs(e));           { 1 }
  writeln(x);
  writeln(not Int64(e));      { 0  — IR_NOT }
  ShowI64(Length('abc'));     { 3 }
  writeln('OK');
end.
