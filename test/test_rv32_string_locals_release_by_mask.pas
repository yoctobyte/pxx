program test_rv32_string_locals_release_by_mask;
{ On riscv32 --platform=esp a proc's string locals are released at scope exit
  a 32-slot window at a time, by one PXXStrDecRefMask call per window, rather
  than a load and a PXXStrDecRef call each. Every local must still be released
  exactly once: the refcount of the shared handle g is printed inside and after
  each call, so a release missed or doubled shows as a wrong count (or a
  crash). Windows over 32 slots, integer locals in the gaps, by-value / const /
  var string parameters, a string result, an early Exit, and a raise through
  the scope exit. Prints the same on x64. }
{$mode objfpc}
uses SysUtils;

var
  g: string;

function RC: NativeInt;
begin
  Result := PNativeInt(PXXHdrRC(Pointer(g)))^;
end;

procedure Many;
var
  s1, s2, s3, s4, s5, s6, s7, s8, s9, s10: string;
  n1, n2, n3: LongInt;
  t1, t2, t3, t4, t5, t6, t7, t8, t9, t10: string;
  big: array[0..20] of LongInt;
  u1, u2, u3, u4, u5, u6, u7, u8, u9, u10: string;
  v1, v2, v3, v4, v5, v6, v7, v8, v9, v10: string;
begin
  s1 := g; s2 := g; s3 := g; s4 := g; s5 := g; s6 := g; s7 := g; s8 := g; s9 := g; s10 := g;
  n1 := 1; n2 := 2; n3 := 3;
  t1 := g; t2 := g; t3 := g; t4 := g; t5 := g; t6 := g; t7 := g; t8 := g; t9 := g; t10 := g;
  big[0] := n1 + n2 + n3; big[20] := big[0];
  u1 := g; u2 := g; u3 := g; u4 := g; u5 := g; u6 := g; u7 := g; u8 := g; u9 := g; u10 := g;
  v1 := g; v2 := g; v3 := g; v4 := g; v5 := g; v6 := g; v7 := g; v8 := g; v9 := g; v10 := g;
  writeln('many in: ', RC, ' ', big[20], ' ', s1 + t5 + u10 + v7);
end;

function Join(a: string; const b: string; var c: string; k: LongInt): string;
var x, y, z: string;
begin
  x := a; y := b; z := c;
  if k = 0 then Exit(x + '|' + y);
  c := g;
  Result := x + y + z + IntToStr(RC);
end;

procedure Raiser(k: LongInt);
var p, q, r: string;
begin
  p := g; q := g; r := g;
  if k > 1 then raise Exception.Create(p + q + r);
  writeln('raiser ok: ', RC);
end;

procedure Two;
var a: string;
    pad: array[0..40] of LongInt;
    b: string;
begin
  a := g; pad[0] := 7; pad[40] := pad[0]; b := g;
  writeln('two in: ', RC, ' ', pad[40]);
end;

var
  w, r: string;
  i: LongInt;

begin
  g := Copy('hello world', 1, 5);
  writeln('start: ', RC);
  Many;
  writeln('after many: ', RC);
  w := g;
  r := Join(g, g, w, 0);
  writeln('join0: ', r, ' ', RC);
  r := Join(g, g, w, 1);
  writeln('join1: ', r, ' ', RC);
  r := '';
  w := '';
  writeln('cleared: ', RC);
  for i := 1 to 2 do
  begin
    try
      Raiser(i);
    except
      on e: Exception do writeln('caught: ', e.Message);
    end;
    writeln('after raiser ', i, ': ', RC);
  end;
  Two;
  writeln('after two: ', RC);
  for i := 1 to 100 do Many;
  writeln('after 100: ', RC);
end.
