program test_an_open_array_parameter_takes_no_default_in_a_class_method_fail;
{ bug-p-a-default-value-is-accepted-on-an-open-array-parameter -- MUST NOT COMPILE.

  THIS IS THE ONE THAT RAN. Declared in a class body and implemented WITHOUT the
  default, it compiled clean, printed High(a) = 1073741823, and segfaulted on
  the next call -- measured 2026-09-06. The refusal that existed lived in
  ParseSubroutine, which parses the IMPLEMENTATION header, so writing the
  default in both places was caught and writing it in the declaration alone was
  not. The default is written HERE ONLY, deliberately: that is the spelling the
  old guard could not see. }
type
  TC = class
    procedure M(const a: array of string = 'x');
  end;
procedure TC.M(const a: array of string);
begin
  WriteLn(Length(a));
end;
var o: TC;
begin
  o := TC.Create;
  o.M;
  o.Free;
end.
