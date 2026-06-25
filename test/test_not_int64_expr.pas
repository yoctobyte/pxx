program test_not_int64_expr;

{ `not` on an Int64 EXPRESSION (cast / arithmetic / shift) must be the bitwise
  complement, not a boolean. Previously only `not <var>` / `not <lit>` were
  bitwise; `not Int64(0)` even printed TRUE. See bug-not-on-int64-is-boolean.
  LongWord complement is checked by comparison (not writeln) to stay portable —
  arm32 has a separate writeln(LongWord) display bug. }

var
  x, r: Int64;
  c: LongWord;
begin
  x := 5;
  r := not x;            writeln(r);   { -6 }
  r := not (x);          writeln(r);   { -6 }
  r := not (x - 1);      writeln(r);   { -5 }
  r := not (x shr 1);    writeln(r);   { -3 }
  r := not (x + 1);      writeln(r);   { -7 }
  r := not (x * 2);      writeln(r);   { -11 }
  r := not (x shl 1);    writeln(r);   { -11 }
  r := not Int64(5);     writeln(r);   { -6 }
  r := not Int64(0);     writeln(r);   { -1 }

  { LongWord (32-bit unsigned) cast complement, verified by value not display. }
  c := not LongWord(0);
  if c = 4294967295 then writeln('ok-lw0') else writeln('bad-lw0');
  c := not Cardinal(1);
  if c = 4294967294 then writeln('ok-lw1') else writeln('bad-lw1');

  { Boolean `not` must stay logical (no regression). }
  if not (x = 6) then writeln('ok-bool') else writeln('bad-bool');
end.
