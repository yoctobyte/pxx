{$mode objfpc}
program test_var_open_array_field;

{ A static-array RECORD FIELD passed to a `var`/`out` open-array parameter
  (bug-var-open-array-fixed-arg-length, the field case — synapse synacode's
  MD5 MDContext.BufAnsiChar / BufLong). copy-in / copy-out is keyed off the
  argument's address (IRLowerAddress), so it works for a field just like a
  simple var: High/indexing read the field's data, and the callee's writes
  propagate back to the field. FPC oracle: 256 / 1284. }

type
  TCtx = record
    BufByte: array[0..63] of Byte;
    BufLong: array[0..15] of Integer;
  end;

procedure B2L(var ArByte: array of Byte; var ArLong: array of Integer);
var n: Integer;
begin
  for n := 0 to High(ArLong) do
    ArLong[n] := ArByte[n * 4] + (ArByte[n * 4 + 1] shl 8);
end;

var
  c: TCtx;
  i: Integer;
begin
  for i := 0 to 63 do c.BufByte[i] := i;
  for i := 0 to 15 do c.BufLong[i] := 0;
  B2L(c.BufByte, c.BufLong);          { reads BufByte field, writes BufLong field }
  WriteLn(c.BufLong[0]);              { 0 + (1 shl 8)  = 256 }
  WriteLn(c.BufLong[1]);              { 4 + (5 shl 8)  = 1284 }
end.
