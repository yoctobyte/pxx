program test_empty_class_shorthand;
{ FPC shorthand: `T = class(TBase);` with no body and no `end`. }
uses sysutils;

type
  EBase = class(Exception);
  EDerived = class(EBase);

var
  caught: Boolean;
  msg: string;
begin
  caught := False;
  try
    raise EBase.Create('base error');
  except
    on E: EBase do
    begin
      caught := True;
      msg := E.Message;
    end;
  end;
  if caught then writeln('EBase ok: ' + msg)
  else writeln('EBase FAIL');

  caught := False;
  try
    raise EDerived.Create('derived error');
  except
    on E: EDerived do
    begin
      caught := True;
      msg := E.Message;
    end;
  end;
  if caught then writeln('EDerived ok: ' + msg)
  else writeln('EDerived FAIL');
end.
