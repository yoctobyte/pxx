comment Algol 60 frontend skeleton test (feature-esoteric-algol probe);
begin
  integer i, n, k;
  real x;
  Boolean f;
  comment counting for with step, inclusive until;
  n := 0;
  for i := 1 step 1 until 10 do
    n := n + i;
  outinteger(1, n);
  k := 0;
  for i := 10 step -2 until 2 do
    k := k + i;
  outinteger(1, k);
  x := 2.5;
  x := x * 4.0 + 0.5;
  outreal(1, x);
  f := n = 55 and k = 30;
  if f then
    outstring(1, 'kinship holds')
  else
    outstring(1, 'kinship BROKEN');
  while n > 40 do
  begin
    n := n - 5
  end;
  outinteger(1, n)
end
