program test_cross_ptr_arith;
{ Deref of a parenthesised expression — (p)^, (p+k)^, (p-k)^ — and element-scaled
  pointer arithmetic with positive AND negative offsets. `(p)^` used to leave the
  `^` dangling (returned the pointer, not the pointee); negative offsets were not
  sign-extended. Output must be byte-identical on every target. }
var a: array[0..7] of Integer;
    p: ^Integer; i, s: Integer;
function ViaPtr(q: ^Integer; off: Integer): Integer;
begin ViaPtr := (q + off)^; end;
begin
  for i := 0 to 7 do a[i] := i * 11;
  p := @a[4];
  writeln('deref=', p^);
  writeln('paren=', (p)^);
  writeln('plus1=', (p + 1)^);
  writeln('minus1=', (p - 1)^);
  writeln('plus0=', (p + 0)^);
  writeln('minus2=', (p - 2)^);
  { negative offset via a variable }
  i := -3;
  writeln('varneg=', (p + i)^);
  { through a function param }
  writeln('fn+2=', ViaPtr(p, 2));
  writeln('fn-4=', ViaPtr(p, -4));
  { sum across a sweep using negative-to-positive offsets }
  s := 0;
  for i := -4 to 3 do s := s + (p + i)^;
  writeln('sweep=', s);
end.
