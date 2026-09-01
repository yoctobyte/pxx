program test_variadic_elision_method_refusal;
{ MUST NOT COMPILE. A bracketed vector followed by more arguments is a genuine
  arity error, not an elided tail: absorbing it would build a vector whose
  first element is a vector, which the resolver accepts in silence.
  The `do not wrap a wrap` guard in AbsorbVariadicTailArgs is what refuses it,
  and this file is that guard's positive control -- the method slice of
  feature-writeln-as-library. }
type
  TL = class
    function D(const a: array of const): string;
  end;
function TL.D(const a: array of const): string;
begin
  Result := '';
end;
var g: TL;
begin
  g := TL.Create;
  WriteLn(g.D(['already', 1], 2));
end.
