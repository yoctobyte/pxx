program test_object_ref_array_identity;

type
  TObject = class
  end;

  TButton = class(TObject)
  end;

  TForm = class
  public
    Btns: array of TButton;
    Names: array of AnsiString;
    Hit: AnsiString;
    procedure Click(Sender: TObject);
  end;

procedure TForm.Click(Sender: TObject);
var
  i: Integer;
begin
  Hit := '';
  for i := 0 to Length(Btns) - 1 do
    if Sender = Btns[i] then
    begin
      Hit := Names[i];
      Exit;
    end;
end;

var
  f: TForm;
begin
  f := TForm.Create;
  SetLength(f.Btns, 2);
  SetLength(f.Names, 2);
  f.Btns[0] := TButton.Create;
  f.Btns[1] := TButton.Create;
  f.Names[0] := 'A';
  f.Names[1] := 'B';
  f.Click(f.Btns[1]);
  writeln(f.Hit);
end.
