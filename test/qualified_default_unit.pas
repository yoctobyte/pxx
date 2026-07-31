unit qualified_default_unit;

{ bug-nilpy-qualified-proc-omitted-default: a unit-level proc called
  QUALIFIED (unit.proc(...)) used to require every parameter filled, even a
  trailing DEFAULTED one -- fixed alongside TryFillTrailingDefaults. }

interface

procedure show(const text: AnsiString; const opts: Integer = 0);
procedure show2(const text: AnsiString; const opts: Integer = 0; const flag: Boolean = False);

implementation

procedure show(const text: AnsiString; const opts: Integer = 0);
begin
  WriteLn(text, ' ', opts);
end;

procedure show2(const text: AnsiString; const opts: Integer = 0; const flag: Boolean = False);
begin
  WriteLn(text, ' ', opts, ' ', flag);
end;

end.
