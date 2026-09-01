program test_array_of_const_string_leaks;
{ An `array of const` element of type AnsiString gets an OWNER.

  A TVarRec slot is a bare pointer union -- the record carries no managed field
  and no finaliser -- so a string that arrives at the slot carrying a +1 nobody
  holds can never be released: no scope-exit scan can see it, because it was
  never a symbol. Every element built by an EXPRESSION leaked exactly one handle
  per call. An element that names a local was already clean, because the local
  owned it; that row is the control that says the leak is about ownership and
  not about the constructor.

  live before -> after, measured one arm per program, 1000 trips each, on a
  baseline built by reverting the ir.inc hunk and rebuilding to `converged`
  (8e853c4cba34) against the fixed binary (e7fb90cccb94):
    TakeC(['lit' + c, i])                       1003 -> 5   allocs  3000
    Format('%s-%d', ['lit' + c, i])              903 -> 7    allocs  9755
    Format('%s-%d', [IntToStr(i * 100000), i])   995 -> 7    allocs 17582
    TakeC([t, i])       t a named AnsiString       4 -> 5    allocs  1871
    TakeC(['plain literal', i])                    4 -> 4    allocs  1871
  allocs is unchanged on every row -- same traffic, so the delta is ownership.
  This whole program: 2977 -> 10 against a bound of 50.

  The +1 on the named control is the LAST trip's value still held by the hidden
  temp at program exit, exactly as `t` holds it: the same two arms inside a
  PROCEDURE come back live=7 in 3799 allocs, so the temp is released at scope
  exit and only the main block's residue stays. It is a constant, not per-trip.

  The printed tail is here so expect_same has something to compare across
  targets, but it is NOT what catches this bug -- the pre-fix binary prints the
  identical tail on all five targets while leaking. Only the absolute bound in
  assert_no_leak sees it.
  bug-a-a-computed-string-in-an-array-of-const-leaks-its-temporary }
{$mode objfpc}{$H+}
uses sysutils;

const N = 1000;

var i, sink: Integer;
    c: Char;
    t, s: AnsiString;

procedure TakeC(const a: array of const);
begin
  { reads the array, keeps nothing }
  if Length(a) > 0 then Inc(sink, Length(a));
end;

begin
  sink := 0;

  { computed element, constructor in argument position }
  for i := 1 to N do
  begin
    c := Chr(48 + i mod 10);
    TakeC(['lit' + c, i]);
  end;

  { the same constructor as Format's second argument }
  for i := 1 to N do
  begin
    c := Chr(48 + i mod 10);
    s := Format('%s-%d', ['lit' + c, i]);
    Inc(sink, Length(s));
  end;

  { element is a function RESULT rather than a concat }
  for i := 1 to N do
  begin
    s := Format('%s-%d', [IntToStr(i * 100000), i]);
    Inc(sink, Length(s));
  end;

  { CONTROL: element names a local, which already owned it }
  for i := 1 to N do
  begin
    c := Chr(48 + i mod 10);
    t := 'lit' + c;
    TakeC([t, i]);
  end;

  { CONTROL: a frozen inline literal allocates nothing }
  for i := 1 to N do
    TakeC(['plain literal', i]);

  WriteLn('sink=', sink);
  WriteLn('tail=', s);
end.
