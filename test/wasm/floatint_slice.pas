{ Frac/Int on wasm32, compared against native. Values are printed as scaled
  INTEGERS because writing a float is a separate gap on this target ("the RTL
  writers take a double by address and this arm does not spill one yet") --
  encoding the result sidesteps that without weakening what is being asserted. }
program fi;
var d: Double; s: Single; i: Integer;
procedure Show(const nm: string; a, b: Double);
begin
  WriteLn(nm, ' int=', Trunc(a * 10000), ' frac=', Trunc(b * 10000));
end;
begin
  d := 3.75;      Show('pos   ', Int(d), Frac(d));
  d := -3.75;     Show('neg   ', Int(d), Frac(d));
  d := 0.0;       Show('zero  ', Int(d), Frac(d));
  d := -0.25;     Show('negfr ', Int(d), Frac(d));
  d := 1e9 + 0.5; Show('big   ', Int(d), Frac(d));
  i := 7;         Show('intarg', Int(i), Frac(i));
  s := 2.5;       Show('single', Int(s), Frac(s));
  { nested: the inner Frac must not clobber the outer one's saved copy }
  d := 5.25;      Show('nested', 0, Frac(Frac(d) + 10.5));
  WriteLn('done');
end.
