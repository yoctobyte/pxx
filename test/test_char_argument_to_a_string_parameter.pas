program test_char_argument_to_a_string_parameter;
{ A Char-shaped argument handed to a `string` parameter converts. Two shapes,
  one destination: a static `array of Char`, and a plain `Char` VALUE.

  The Char VALUE was REFUSED, with a message that was correct about a different
  parameter: `a Char VALUE is not a PChar -- only a character CONSTANT converts
  (fpc refuses this too)`. True of a PChar parameter; false of a string one --
  fpc 3.2.2 prints `Q` and length 1 for row A. The predicate that gated the
  refusal answers "does this parameter take a char literal as a string", and a
  frozen-string parameter answers yes to it just as a PChar does, so one
  refusal served two questions.

  The ARRAY shape had a second, independent block: the arg-loop conversion
  tested `TypeKind in [tyString, tyAnsiString]`, and `string[N]` is
  tyShortString/tyFixedString, so it fell out of the enumerated set. Both had
  to go for row C.

  .expected is fpc 3.2.2's own output.

  ROW A IS THE ONE THAT WAS A DIAGNOSTIC AND BECAME A VALUE, and it is why the
  conversion arm exists rather than just the deletion of the refusal: with the
  refusal scoped to the pointer destination and nothing put in its place, this
  row printed an EMPTY string. A wrong value where there used to be a wrong
  message is the worse of the two.

  ROW E IS THE REGRESSION CONTROL for the refusal that stays. A Char variable
  passed where a PChar is expected still has no safe meaning -- the ordinal
  goes where a pointer is read -- and it lives in the _fail sibling
  test_char_value_to_a_pchar_parameter_fail.pas. }
type
  CharA4  = array[1..4] of Char;
  String4 = String[4];
var
  c: Char;
  a: CharA4;
  s: String4;

procedure ByVal(st: String4);   begin WriteLn('byval=[', st, '] len=', Length(st)); end;
procedure ByConst(const st: String4); begin WriteLn('byconst=[', st, '] len=', Length(st)); end;
procedure Ansi(st: AnsiString); begin WriteLn('ansi=[', st, '] len=', Length(st)); end;

begin
  c := 'Q';
  a := 'ABCD';

  ByVal(c);      { A — a Char VALUE, not a literal }
  ByConst(c);    { B }
  Ansi(c);       { C is below; this is the managed destination for the same value }

  ByVal(a);      { C — the array shape into a frozen destination }
  ByConst(a);    { D }
  Ansi(a);

  { and the assignment path, which always worked — the row that says the
    argument path is what changed, not the conversion itself }
  s := a;
  WriteLn('assign=[', s, '] len=', Length(s));
end.
