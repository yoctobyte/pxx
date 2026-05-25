program RecordStringField;

type
  TToken = record
    Kind: Integer;
    SVal: AnsiString;
    IVal: Integer;
    Line: Integer;
  end;

function FieldType(rec: Integer; const field: AnsiString): Integer;
begin
  FieldType := 1;
  if rec = 3 then
  begin
    if field = 'SVal' then FieldType := 4;
  end;
end;

var
  tok: TToken;

begin
  tok.SVal := 'CodePos';
  writeln(FieldType(3, tok.SVal));
  tok.SVal := 'SVal';
  writeln(FieldType(3, tok.SVal));
end.
