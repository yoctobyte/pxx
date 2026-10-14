program test_rv32_store_through_a_frame_address;
{ On riscv32 a store whose address is a frame slot's own address, or a
  pointer/integer frame local plus a constant, loads that address into a1
  after the value and stores at the constant offset, with no push of the
  value. Byte, half and word widths, field offsets, negative constants, and
  values that call (so they are not leaves). Prints the same on x64. }
{$mode objfpc}
type
  TRec = record
    a: Byte;
    b: Word;
    c: LongInt;
    d: LongInt;
  end;
  PRec = ^TRec;
  TObj = class
    x, y: LongInt;
    z: Byte;
  end;

var calls: Integer;

function Val(n: LongInt): LongInt;
begin
  Inc(calls);
  Result := n * 3 + calls;
end;

procedure Run;
var
  buf: array[0..15] of LongInt;
  p: PLongInt;
  pb: PByte;
  pw: PWord;
  base: Int64;
  r: TRec;
  pr: PRec;
  o: TObj;
  i: Integer;
begin
  for i := 0 to 15 do buf[i] := 0;
  p := @buf[2];
  p^ := Val(10);
  PLongInt(PtrUInt(p) + 4)^ := Val(20);
  PLongInt(PtrUInt(p) - 8)^ := Val(30);
  pb := PByte(@buf[6]);
  pb^ := Byte(Val(40));
  PByte(PtrUInt(pb) + 3)^ := Byte(Val(50) + 200);
  pw := PWord(@buf[8]);
  pw^ := Word(Val(60) * 1000);
  PWord(PtrUInt(pw) + 2)^ := Word(Val(70) - 1);
  base := Int64(PtrUInt(@buf[10]));
  PLongInt(base)^ := Val(80);
  PLongInt(base + 4)^ := Val(90);
  PLongInt(base + 8)^ := -Val(100);
  for i := 0 to 15 do write(buf[i], ' ');
  writeln;

  r.a := Byte(Val(1)); r.b := Word(Val(2) + 65000); r.c := Val(3); r.d := -Val(4);
  writeln('rec: ', r.a, ' ', r.b, ' ', r.c, ' ', r.d);
  pr := @r;
  pr^.c := Val(5) + 1;
  pr^.a := Byte(Val(6) + 250);
  pr^.b := Word(Val(7));
  writeln('ptr: ', r.a, ' ', r.b, ' ', r.c, ' ', r.d);
  o := TObj.Create;
  o.x := Val(8); o.y := Val(9) * 2; o.z := Byte(Val(11));
  writeln('obj: ', o.x, ' ', o.y, ' ', o.z);
  o.Free;
end;

begin
  calls := 0;
  Run;
  writeln('calls: ', calls);
end.
