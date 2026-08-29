{ Ordinary Pascal. Uses the RTL textfile unit and declares `var f: Text`, so
  SizeOf(f) must be the file RECORD's size regardless of what any OTHER unit
  declared, and regardless of the order a NilPy program imported them. This
  unit never names importordertextcls.
  bug-nilpy-import-order-leaks-a-class-name-into-a-later-compiled-rtl-unit }
unit importordertextuse;
interface
uses textfile;
procedure ShowTextSize;
implementation
procedure ShowTextSize;
var f: Text;
begin
  { > 4000 rather than the exact 4128: the assertion is "the file record, not an
    8-byte class pointer", and pinning the record's exact layout here would make
    this test fail for a reason it is not about. }
  if SizeOf(f) > 4000 then WriteLn('text-is-the-file-record')
  else WriteLn('WRONG: rebound to something ', SizeOf(f), ' bytes');
end;
end.
