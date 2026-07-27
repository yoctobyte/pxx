program test_nativeint_cast_field;
{ NativeUInt(rec.someInteger) must load the FIELD's four bytes and widen, not
  eight bytes at the field's address — the extra four belong to whatever field
  the record declares next, and the cast is where the corruption entered.
  Int64/UInt64 already widened correctly; the pointer-sized pair did not, so
  every mask built with `NativeUInt(FHashCap) - 1` carried bit 32 whenever the
  neighbouring Boolean was True. }
type
  TR = class
    n: Integer;
    b: Boolean;
  end;
var
  r: TR;
  m: NativeUInt;
begin
  r := TR.Create;
  r.n := 16;
  r.b := True;
  WriteLn(Int64(NativeUInt(r.n)));
  WriteLn(Int64(NativeInt(r.n)));
  WriteLn(Int64(PtrUInt(r.n)));
  WriteLn(Int64(QWord(r.n)));
  WriteLn(Int64(Cardinal(r.n)));
  m := NativeUInt(r.n) - 1;
  WriteLn(Int64(m));
  WriteLn(Int64(NativeUInt(r.n) and m));
end.
