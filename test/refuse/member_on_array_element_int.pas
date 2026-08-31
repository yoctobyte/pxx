program member_on_array_element_int;
{ The same hole with a non-managed element type, where the old behaviour was
  quieter and therefore worse: the selector was silently DROPPED and the
  program printed the element itself, so the typo had no observable effect at
  all. A second member (`.AndAnother`) is chained on purpose — the whole tail
  was being discarded, not just one step. }
var ai: array[0..1] of Integer;
begin
  ai[0] := 7;
  WriteLn(ai[0].NoSuch.AndAnother);
end.
