unit myrand;
{ A used unit that shadows the System builtin `Random` by name. Its Random
  returns n*10 (deterministic, distinct from the builtin generator) so the test
  can see WHICH implementation a call bound to. }
interface
function Random(n: Integer): Integer;
procedure RandSeed(s: LongWord);
implementation
var st: LongWord;
procedure RandSeed(s: LongWord); begin st := s; end;
function Random(n: Integer): Integer; begin Result := n * 10; end;
end.
