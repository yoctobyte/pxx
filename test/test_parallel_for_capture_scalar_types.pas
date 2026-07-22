program test_parallel_for_capture_scalar_types;
{ Captured non-Integer scalars passed to a typed callee parameter from a
  `parallel for` body (bug-parallel-for-captured-boolean-loses-type). The
  worker's capture accessor is declared `capj: ^<TypeName>` via a SYNTHETIC
  ident token; ParseTypeKind's ident arm lacked the keyword-token builtins
  (Boolean/Integer/Char/Single/Double), so the caret element type defaulted
  and a captured Boolean arrived at overload resolution as an Integer —
  a compile error on the ordinary Sink(i, flag) pattern. }
uses palparallel;

var okB, okC, okY, okS, okD: Integer;

procedure SinkB(i: Integer; flag: Boolean); begin if flag then okB := 1; end;
procedure SinkC(i: Integer; c: Char);       begin if c = 'x' then okC := 1; end;
procedure SinkY(i: Integer; b: Byte);       begin if b = 200 then okY := 1; end;
procedure SinkS(i: Integer; s: Single);     begin if (s > 1.4) and (s < 1.6) then okS := 1; end;
procedure SinkD(i: Integer; d: Double);     begin if d = 2.5 then okD := 1; end;

procedure Run;
var i: Integer; lb: Boolean; lc: Char; ly: Byte; ls: Single; ld: Double;
begin
  lb := True; lc := 'x'; ly := 200; ls := 1.5; ld := 2.5;
  parallel for i := 0 to 9 do SinkB(i, lb);
  parallel for i := 0 to 9 do SinkC(i, lc);
  parallel for i := 0 to 9 do SinkY(i, ly);
  parallel for i := 0 to 9 do SinkS(i, ls);
  parallel for i := 0 to 9 do SinkD(i, ld);
  if okB + okC + okY + okS + okD = 5 then
    writeln('PARFORSCALARTYPES OK')
  else
    writeln('PARFORSCALARTYPES FAIL ', okB, okC, okY, okS, okD);
end;

begin
  Run;
end.
