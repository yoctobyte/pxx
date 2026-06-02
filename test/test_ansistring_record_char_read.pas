{$define PXX_MANAGED_STRING}
program test_ansistring_record_char_read;

type
  TEntry = record
    Text: AnsiString;
  end;

var
  e: TEntry;
  c: Char;

procedure Check(ok: Boolean);
begin
  if ok then writeln(1) else writeln(0);
end;

begin
  e.Text := 'abc';
  c := e.Text[2];
  Check(c = 'b');
  Check(e.Text[1] = 'a');
  Check(e.Text[3] = 'c');
end.
