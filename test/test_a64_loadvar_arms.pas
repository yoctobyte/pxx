program LoadVarArms;
{ Exercises every arm of EmitLoadVarA64, because the scratch-register collapse
  changes the encodings of three of them and the local/param arm not at all.
  The point is the GLOBAL and BY-REF arms: those are the ones that used x1. }
type
  TRec = record a, b: Integer; end;
var
  { globals of every width and signedness the sz/sgn ladder distinguishes }
  gI8:  ShortInt;  gU8:  Byte;
  gI16: SmallInt;  gU16: Word;
  gI32: LongInt;   gU32: LongWord;
  gI64: Int64;
  gPtr: Pointer;
  gSingle: Single;
  gDouble: Double;
  gDyn: array of Integer;
  gStr: AnsiString;
  gRec: TRec;
  gBool: Boolean;
  gChar: Char;

procedure ByRefInt(var x: LongInt; var y: Int64);
begin
  { by-ref param loads: used to deref through x1 }
  WriteLn('byref int  ', x, ' ', y);
  x := x + 1;
  y := y + 1;
  WriteLn('byref int  ', x, ' ', y);
end;

procedure ByRefNarrow(var a: ShortInt; var b: Byte; var c: SmallInt; var d: Word);
begin
  WriteLn('byref narrow ', a, ' ', b, ' ', c, ' ', d);
  a := a - 1; b := b + 1; c := c - 1; d := d + 1;
  WriteLn('byref narrow ', a, ' ', b, ' ', c, ' ', d);
end;

procedure ByRefSingle(var s: Single; var dd: Double);
begin
  { the tySingle by-ref arm — the narrowest path through the helper }
  WriteLn('byref single ', s:0:4, ' ', dd:0:4);
  s := s * 2.0;
  dd := dd * 2.0;
  WriteLn('byref single ', s:0:4, ' ', dd:0:4);
end;

procedure ByRefDyn(var a: array of Integer);
begin
  WriteLn('byref dyn len=', Length(a), ' [0]=', a[0]);
end;

procedure ByRefStr(var s: AnsiString);
begin
  WriteLn('byref str  ', s);
  s := s + '!';
  WriteLn('byref str  ', s);
end;

{ globals read INSIDE a binop, both operand positions — the shape the
  leaf-operand collapse will put on this helper once it takes a destination. }
function GlobalBinops: Int64;
var acc: Int64;
begin
  acc := 0;
  acc := acc + gI32 + gI64;
  acc := acc + Int64(gI8) - Int64(gU8);
  acc := acc + Int64(gI16) - Int64(gU16);
  acc := acc + Int64(gU32);
  acc := acc + gI32 * 3;
  acc := acc - 7 * gI64;
  if gI32 > gI16 then acc := acc + 1000;
  if gU8 < gU16 then acc := acc + 2000;
  GlobalBinops := acc;
end;

var
  lS: Single;
  lD: Double;
  i: Integer;
begin
  gI8 := -100;  gU8 := 200;
  gI16 := -30000; gU16 := 60000;
  gI32 := -2000000000; gU32 := 4000000000;
  gI64 := -9000000000000000000;
  gSingle := 1.25; gDouble := 2.5;
  gBool := True; gChar := 'Z';
  gStr := 'global';
  gRec.a := 11; gRec.b := 22;
  SetLength(gDyn, 4);
  for i := 0 to 3 do gDyn[i] := i * 100;

  WriteLn('globals    ', gI8, ' ', gU8, ' ', gI16, ' ', gU16);
  WriteLn('globals    ', gI32, ' ', gU32, ' ', gI64);
  WriteLn('globals    ', gSingle:0:4, ' ', gDouble:0:4);
  WriteLn('globals    ', gBool, ' ', gChar, ' ', gStr);
  WriteLn('globals    ', gRec.a, ' ', gRec.b);
  WriteLn('globals    dyn len=', Length(gDyn), ' [3]=', gDyn[3]);
  WriteLn('binops     ', GlobalBinops);

  ByRefInt(gI32, gI64);
  ByRefNarrow(gI8, gU8, gI16, gU16);
  ByRefSingle(gSingle, gDouble);
  ByRefDyn(gDyn);
  ByRefStr(gStr);

  { local Single, so the same arm is proved on the local side too }
  lS := 3.5; lD := 4.5;
  WriteLn('locals     ', lS:0:4, ' ', lD:0:4);
  ByRefSingle(lS, lD);
  WriteLn('locals     ', lS:0:4, ' ', lD:0:4);

  WriteLn('after      ', gI8, ' ', gU8, ' ', gI16, ' ', gU16, ' ', gI32, ' ', gI64);
  WriteLn('after      ', gSingle:0:4, ' ', gDouble:0:4, ' ', gStr);
  WriteLn('binops     ', GlobalBinops);
end.
