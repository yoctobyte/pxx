program test_cross_setlen_varparam;

{ Cross-target SetLength on a `var` named-dynamic-array parameter. A resizable
  dynamic-array param (declared via a named `array of T` type, NOT an open
  `array of T`) is passed by the by-ref-handle ABI: the callee receives the
  address of the caller's handle slot, so SetLength inside the callee resizes
  and publishes the new handle back to the caller. Grow preserves the existing
  prefix and zero-fills the tail; shrink keeps min(old,new). Exercised for both
  an integer element type and a managed-AnsiString element type. Output is
  identical on every target (i386/aarch64/arm32) as on x86-64 (the oracle). }

type
  TIntArr = array of Integer;
  TStrArr = array of AnsiString;

procedure GrowI(var a: TIntArr; n: Integer);
begin
  SetLength(a, n);
end;

procedure GrowS(var a: TStrArr; n: Integer);
begin
  SetLength(a, n);
end;

var
  a: TIntArr;
  s: TStrArr;
  i: Integer;
begin
  SetLength(a, 3);
  a[0] := 11; a[1] := 22; a[2] := 33;

  GrowI(a, 5);                 { grow: keep 11,22,33 then 0,0 }
  writeln('grow len=', Length(a));
  for i := 0 to Length(a) - 1 do writeln(a[i]);

  GrowI(a, 2);                 { shrink: keep 11,22 }
  writeln('shrink len=', Length(a));
  for i := 0 to Length(a) - 1 do writeln(a[i]);

  GrowS(s, 2);
  s[0] := 'hello'; s[1] := 'world';
  writeln('s len=', Length(s));
  for i := 0 to Length(s) - 1 do writeln(s[i]);
end.
