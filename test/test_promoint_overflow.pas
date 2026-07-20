program test_promoint_overflow;
{ A promotable int PROMOTES past Int64 rather than wrapping or trapping: 25! is
  exact. Before the heap tier this raised RE 215; before the type existed it
  printed 25! mod 2^64 (7034535277573963776). }
var a: PromoInt;
    i: Integer;
begin
  a := 1;
  for i := 1 to 25 do
    a := a * i;
  Writeln(a);
end.
