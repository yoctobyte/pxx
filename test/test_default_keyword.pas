{$define PXX_MANAGED_STRING}
program test_default_keyword;

type
  TRec = record
    s: AnsiString;
    n: Integer;
  end;

procedure Check(ok: Boolean);
begin
  if ok then writeln(1) else writeln(0);
end;

var
  i: Integer;
  s: string;
  p: Pointer;
  r: TRec;

begin
  i := 42;
  i := default;
  Check(i = 0);

  s := 'hello';
  s := default;
  Check(s = '');
  Check(Length(s) = 0);

  GetMem(p, 8);
  Check(p <> nil);
  p := default;
  Check(p = nil);

  r.s := 'managed';
  r.n := 7;
  r := default;
  Check(r.s = '');
  Check(Length(r.s) = 0);
  Check(r.n = 0);
end.
