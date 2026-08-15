program test_i386_float_params;

{ i386 float parameter ABI, checked against x86-64 as the oracle (the Makefile
  runs this source on both and diffs the output).

  By-REFERENCE float params are the regression half: a `var/out r: Double` is a
  POINTER in one 4-byte slot, not an 8-byte value. The caller used to run the
  float path over it (cvtsi2sd of the address, pushed as a double) and the
  callee's prologue used to copy 8 bytes into the 4-byte slot — clobbering the
  saved ebp — so every read or write through such a param segfaulted.
  `var Single`, `out`, and a two-out-param split are the shapes that showed it. }

function CheckMix(a: Integer; b: Double; c: Integer): Integer;
begin
  if (a = 3) and (b > 2.49) and (b < 2.51) and (c = 7) then
    CheckMix := 1
  else
    CheckMix := 0;
end;

procedure WriteVar(var r: Double);
begin
  r := 1.0;
end;

procedure ReadVar(var r: Double; var o: Double);
begin
  o := r + 2.0;
end;

procedure WriteOut(out r: Double);
begin
  r := 3.5;
end;

procedure WriteVarSingle(var r: Single);
begin
  r := 4.25;
end;

procedure Split(x: Double; var hi, lo: Double);
begin
  hi := x * 2.0;
  lo := x / 2.0;
end;

var
  a, b, c: Double;
  s: Single;

begin
  writeln(CheckMix(3, 2.5, 7));

  a := 0.0;
  WriteVar(a);
  writeln(a:0:5);

  a := 5.0;
  ReadVar(a, b);
  writeln(b:0:5);

  c := 0.0;
  WriteOut(c);
  writeln(c:0:5);

  s := 0.0;
  WriteVarSingle(s);
  writeln(s:0:5);

  Split(3.0, a, b);
  writeln(a:0:5);
  writeln(b:0:5);
end.
