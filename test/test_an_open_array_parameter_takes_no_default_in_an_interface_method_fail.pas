program test_an_open_array_parameter_takes_no_default_in_an_interface_method_fail;
{ bug-p-a-default-value-is-accepted-on-an-open-array-parameter -- MUST NOT COMPILE.

  THE FOURTH PARSER, AND THE ONLY ONE WITH NO SECOND CHANCE: an interface method
  has no implementation header, so ParseSubroutine -- where the refusal used to
  live -- never sees it at all. This declaration alone compiled clean before the
  fix, with no class implementing it and nothing to catch it downstream. }
type
  IFoo = interface
    procedure M(const a: array of string = 'x');
  end;
begin
  WriteLn('declaration compiled');
end.
