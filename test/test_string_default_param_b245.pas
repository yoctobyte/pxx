program test_string_default_param_b245;
{ A default parameter value may be a STRING literal (`msg: string = ''`), not just
  an ordinal — fpcunit's Fail/AssertEquals are declared that way. The default is a
  frozen literal, so a managed `string` param needs the same hidden managed temp an
  explicitly-written literal arg gets; passing the raw literal made Length() read
  the length prefix as data (bug-pascal-string-default-param). }
type
  TBox = class
    procedure Say(const who: string; const msg: string = 'hi'; n: Integer = 3);
  end;

procedure TBox.Say(const who: string; const msg: string = 'hi'; n: Integer = 3);
begin
  writeln(msg, ' ', who, ' ', n, ' len=', Length(msg));
end;

procedure P(a: Integer; msg: string = 'default'; tail: string = '');
begin
  writeln('a=', a, ' msg=', msg, ' len=', Length(msg), ' taillen=', Length(tail));
end;

var b: TBox;
begin
  P(1);
  P(2, 'abc');
  P(3, 'abc', 'zz');
  b := TBox.Create;
  b.Say('bob');
  b.Say('ann', 'yo');
  b.Say('cid', 'hey', 9);
  b.Free;
end.
