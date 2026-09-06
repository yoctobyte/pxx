unit ufpdeep;
{ The forward pointer, TWO `uses` levels away from the program that will be
  compiled. Ordinary Pascal: `PX = ^TX` above TX is how every linked node is
  spelled, and lib/rtl's palsync spells `PMutex = ^TMutex` exactly this way. }
interface

type
  PX = ^TX;
  TX = record v: Integer; end;

procedure FillIt(var x: TX);

implementation

procedure FillIt(var x: TX);
begin
  x.v := 41;
end;

end.
