program test_managed_record_field_string_ops;

{$define PXX_MANAGED_STRING}

type
  TEntry = record
    Name: AnsiString;
    Other: AnsiString;
  end;

procedure Check(ok: Boolean);
begin
  if ok then writeln(1) else writeln(0);
end;

function LenOf(const s: AnsiString): Integer;
begin
  LenOf := Length(s);
end;

procedure Change(var s: AnsiString);
begin
  s := s + '!';
end;

var
  a, b: TEntry;

begin
  a.Name := 'hello';
  Check(Length(a.Name) = 5);
  Check(a.Name[2] = 'e');
  Check(LenOf(a.Name) = 5);

  Change(a.Name);
  Check(a.Name = 'hello!');
  Check(Length(a.Name) = 6);

  b.Other := a.Name;
  Check(b.Other = 'hello!');
  Check(Length(b.Other) = 6);
end.
