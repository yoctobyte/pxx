program test_shortstring_value_parameter_truncates;
{ A `string[N]` VALUE parameter holds at most N characters. It did not.

  The by-value copy at a call boundary goes through a hidden frozen temp, and
  that temp was allocated at capacity 255 unconditionally -- "255 covers every
  string[N], so a wider temp cannot truncate whatever frozen kind the source
  is", which reads as safety and is the bug: truncation IS the semantics of the
  copy. The callee received a ten-character string through a parameter whose
  own SizeOf(st) answers 5, in the same program, silently.

  .expected is fpc 3.2.2's own output, and the four const rows are there
  because FPC's rule is NOT "shortstring parameters truncate". Measured
  2026-09-06:

    by-value, literal          -> truncates      (row A)
    by-value, string[8] var    -> truncates      (row B)
    by-value, AnsiString       -> truncates      (row C)
    const,    literal          -> does NOT       (row D)
    const,    string[8] var    -> does NOT       (row E)
    const,    AnsiString       -> truncates      (row F)

  ROWS D AND E ARE THE ONES WITH TEETH. A fix that simply clamps every frozen
  parameter to its own N passes A, B, C and F and breaks these two -- and D and
  E are the rows nobody thinks to write, because "shortstring parameters
  truncate" is the sentence everyone remembers. `const` binds the original;
  only a CONVERSION materialises a temp, which is why F truncates and E does
  not even though both are `const`.

  ROW G IS THE CAPACITY-CARRIER CONTROL and it is why there are two calls to
  the same routine. The N was first read back from the parameter's own SYMBOL
  (SymStrCap through Params[0].SymIdx) and that answered 4 in a one-call
  program and 255 in this one, because a hidden argument temp had already
  recycled the symbol slot. 4 is the RIGHT answer, so the stale read looked
  correct until a second call site existed. A single-call test cannot fail on
  that, which is the whole reason G exists.
  bug-p-a-string-n-value-parameter-does-not-truncate-to-its-own-capacity }
type
  String4 = String[4];
  String8 = String[8];
var
  s8: String8;
  ans: AnsiString;

procedure ByVal(st: String4);
begin
  WriteLn('byval=[', st, '] len=', Length(st), ' sizeof=', SizeOf(st));
end;

procedure ByConst(const st: String4);
begin
  WriteLn('byconst=[', st, '] len=', Length(st));
end;

begin
  s8  := 'ABCDEFGH';
  ans := 'ABCDEFGH';

  ByVal('literalfar');   { A }
  ByVal(s8);             { B }
  ByVal(ans);            { C }

  ByConst('literalfar'); { D }
  ByConst(s8);           { E }
  ByConst(ans);          { F }

  ByVal(s8);             { G — the same routine a second time; see the note }
end.
