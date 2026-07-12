program test_method_default_param_b246;
{ A method implementation that repeats its default values had them written to the
  WRONG param slot: the implicit-Self injection shifted pnames/ptypes/... but not
  the pdefault* arrays, so each default landed on the previous param. `M` below
  silently produced a=2 on a defaulted call instead of a=1 — wrong values, no
  diagnostic (bug-pascal-method-default-param-self-shift). }
type
  TB = class
    procedure M(a: Integer = 1; b: Integer = 2);
    procedure S(x: Integer; msg: string = 'hi'; n: Integer = 3);
  end;

procedure TB.M(a: Integer = 1; b: Integer = 2);
begin
  writeln('a=', a, ' b=', b);
end;

procedure TB.S(x: Integer; msg: string = 'hi'; n: Integer = 3);
begin
  writeln('x=', x, ' msg=', msg, ' n=', n, ' len=', Length(msg));
end;

var o: TB;
begin
  o := TB.Create;
  o.M;
  o.M(9);
  o.M(9, 8);
  o.S(1);            { both trailing defaults filled, one of them a string }
  o.S(2, 'yo');
  o.S(3, 'hey', 7);
  o.Free;
end.
