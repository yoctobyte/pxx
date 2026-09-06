unit ugra;
{ Generic routines of several ARITIES, declared in a unit so the specializations
  are reached across a uses clause -- the path that actually refused.
  bug-p-a-generic-routine-supports-exactly-one-type-parameter }
{$mode objfpc}
interface

generic procedure Solo<T>(a: T);
generic procedure Pair<T, S>(a: T; b: S);
generic procedure Trio<T, S, U>(a: T; b: S; c: U);

implementation

generic procedure Solo<T>(a: T);
begin WriteLn('solo=', a); end;

generic procedure Pair<T, S>(a: T; b: S);
begin WriteLn('pair=', a, ',', b); end;

generic procedure Trio<T, S, U>(a: T; b: S; c: U);
begin WriteLn('trio=', a, ',', b, ',', c); end;

end.
