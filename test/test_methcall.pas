program TestMethCall;
{ Method pointers: `procedure(...) of object` / `function(...): R of object`.
  A method-pointer value is a 16-byte Code+Data record; calling it injects
  Self (Data) as the hidden first argument and calls Code. (Class instances are
  x86-64 only, so this test is x86-64 only.) }

type
  TCalc = class
    base: Integer;
    procedure Show(x: Integer);
    function AddBase(x, y: Integer): Integer;
    procedure Ping;
  end;

  TIntMeth = procedure(x: Integer) of object;
  TBinMeth = function(x, y: Integer): Integer of object;
  TNoArg   = procedure of object;

procedure TCalc.Show(x: Integer);
begin
  writeln('show ', x, ' base=', base);
end;

function TCalc.AddBase(x, y: Integer): Integer;
begin
  AddBase := base + x + y;
end;

procedure TCalc.Ping;
begin
  writeln('ping base=', base);
end;

var
  c: TCalc;
  m: TIntMeth;
  f: TBinMeth;
  p: TNoArg;
begin
  c := TCalc.Create;
  c.base := 100;

  { statement call, one arg, Self injected }
  m := @c.Show;
  m(42);

  { function method pointer: expression + return value }
  f := @c.AddBase;
  writeln('add ', f(2, 3));
  if f(10, 20) = 130 then writeln('expr ok');

  { no-arg method pointer (called with empty parens) }
  p := @c.Ping;
  p();
end.
