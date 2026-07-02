program test_move_fillchar_nouses;
{ Move / FillChar available with NO uses clause (FPC System parity) — they
  live in the builtin unit, pulled by the bare-name token pre-scan
  (feature-move-fillchar-intrinsics, the proper-home half; the optimized
  intrinsic emission remains that ticket's follow-up). Overlap-safe Move
  (memmove semantics) pinned. }
var
  a, b: array[0..9] of Integer;
  i, okCount: Integer;
procedure Chk(n: Integer; cond: Boolean);
begin
  if cond then begin writeln('ok ', n); okCount := okCount + 1; end
  else writeln('FAIL ', n);
end;
begin
  okCount := 0;
  for i := 0 to 9 do a[i] := i * 11;
  Move(a, b, SizeOf(a));
  Chk(1, (b[0] = 0) and (b[9] = 99));
  Move(a[0], a[2], 5 * SizeOf(Integer));      { overlapping, dest > src: backward copy }
  Chk(2, (a[2] = 0) and (a[6] = 44));
  FillChar(b, SizeOf(b), 0);
  Chk(3, (b[0] = 0) and (b[9] = 0));
  FillChar(b[3], 2 * SizeOf(Integer), $FF);
  Chk(4, (b[3] = -1) and (b[4] = -1) and (b[5] = 0));
  writeln('total ok ', okCount, ' / 4');
end.
