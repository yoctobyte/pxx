{$define PXX_MANAGED_STRING}
program test_nested_dynarray_managed;

type
  TEntry = record
    Text: AnsiString;
    Value: Integer;
  end;

var
  s: array of array of AnsiString;
  sAlias: array of array of AnsiString;
  deep: array of array of array of AnsiString;
  r: array of array of TEntry;

procedure Check(ok: Boolean);
begin
  if ok then writeln(1) else writeln(0);
end;

procedure TestLocal;
var
  ls: array of array of AnsiString;
  lr: array of array of TEntry;
begin
  SetLength(ls, 1);
  SetLength(ls[0], 2);
  ls[0][0] := 'local';
  ls[0][1] := ls[0][0] + ' string';
  Check(ls[0][1] = 'local string');

  SetLength(lr, 1);
  SetLength(lr[0], 1);
  lr[0][0].Text := 'local record';
  lr[0][0].Value := 7;
  Check(lr[0][0].Text = 'local record');
  Check(lr[0][0].Value = 7);
end;

begin
  SetLength(s, 2);
  SetLength(s[0], 2);
  SetLength(s[1], 1);
  s[0][0] := 'zero';
  s[0][1] := 'one';
  s[1][0] := 'two';
  Check(s[0][1] = 'one');
  Check(s[1][0] = 'two');

  SetLength(s[0], 4);
  Check(s[0][0] = 'zero');
  Check(s[0][1] = 'one');
  Check(s[0][3] = '');
  SetLength(s[0], 1);
  Check(s[0][0] = 'zero');
  SetLength(s[1], 0);
  Check(Length(s[1]) = 0);
  SetLength(s, 3);
  Check(s[0][0] = 'zero');
  Check(Length(s[2]) = 0);
  sAlias := s;
  SetLength(s, 0);
  Check(sAlias[0][0] = 'zero');
  SetLength(sAlias, 0);

  SetLength(deep, 1);
  SetLength(deep[0], 1);
  SetLength(deep[0][0], 1);
  deep[0][0][0] := 'depth three';
  Check(deep[0][0][0] = 'depth three');
  SetLength(deep, 0);

  SetLength(r, 2);
  SetLength(r[0], 2);
  SetLength(r[1], 1);
  r[0][0].Text := 'first';
  r[0][0].Value := 10;
  r[0][1].Text := 'second';
  r[1][0].Text := 'third';
  Check(r[0][0].Text = 'first');
  Check(r[0][0].Value = 10);

  SetLength(r[0], 3);
  Check(r[0][1].Text = 'second');
  Check(r[0][2].Text = '');
  r[0][2].Text := 'new';
  Check(r[0][2].Text = 'new');
  SetLength(r[0], 1);
  Check(r[0][0].Text = 'first');
  SetLength(r, 0);
  Check(Length(r) = 0);

  TestLocal;
  Check(Length(s) = 0);
end.
