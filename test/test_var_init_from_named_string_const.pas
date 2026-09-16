program test_var_init_from_named_string_const;
{ A `var` initialised from a NAMED string constant, where the `const` spelling
  of the same declaration always compiled.

  FPC's own compiler/globals.pas:502 is the real case, and it gates 138 of
  FPC's 207 compiler units:

    const defaultmainaliasname = 'main';
    var   mainaliasname : string = defaultmainaliasname;   { "not a constant" }

  THE SHARED HELPER TESTED THE TOKEN KIND INSTEAD OF ASKING THE DESTINATION.
  TryParseInitValForm is the one door the record-field, array-element, const and
  var initialiser paths all go through, and its string arm keyed on
  `CurTok.Kind = tkString` -- a literal and nothing else. A named constant is an
  IDENT, so it fell through to ConstEval, which cannot evaluate a string and does
  not consume it either; the ordinal path then reported `not a constant`.
  TakeStrInitSpan already resolved all three spellings (literal, named
  multi-character const via FindStrConst, and one-character const, which lives in
  the ordinal table and has a span minted for it) and the _decl.inc callers had
  been using it for a while. This door was not.

  THE ROWS ARE CHOSEN SO THE GUARD CAN FAIL, and the boundary is narrow -- this
  is a VAR, STRING-family, from a NAME. Every neighbouring cell already worked
  and is asserted here so the fix cannot have widened into it:

    - Integer, Char and Double from a named const: the ORDINAL path. These must
      not start being read as text. The Char row is the sharp one -- a
      one-character const has a span minted for it by TakeStrInitSpan, so if the
      destination guard were asked after consuming rather than before, `c` would
      hold text and `Ord(c)` would be an address. Ord is asserted for exactly
      that reason, and asserted on BOTH the variable and the constant.
    - a string LITERAL, which took the old arm and must still work.
    - the CONST spelling, which was never broken and is the twin that proves
      this was a missing case and not a missing feature.

  The three string types are separate rows because they are separate storage:
  ShortString is inline bytes, AnsiString is a heap pointer, and `string` follows
  the mode. A fix that pointed all three at one span would still print correctly
  here -- so the LENGTHS are asserted too, which is what would catch a span
  pointing at the wrong end of TokChars. }
const
  KS   = 'main';
  KLONG = 'a longer one';
  KC   = 'A';
  KI   = 42;
  KF   = 1.5;

var
  s1: string     = KS;
  s2: AnsiString = KLONG;
  s3: ShortString = KS;
  s4: string     = 'literal';
  c1: Char       = KC;
  i1: Integer    = KI;
  f1: Double     = KF;

const
  cs: string = KS;

begin
  WriteLn('s1=', s1, ' len=', Length(s1));
  WriteLn('s2=', s2, ' len=', Length(s2));
  WriteLn('s3=', s3, ' len=', Length(s3));
  WriteLn('s4=', s4, ' len=', Length(s4));
  WriteLn('cs=', cs, ' len=', Length(cs));
  { the ordinal neighbours -- Ord on both the var and the const }
  WriteLn('c1=', c1, ' ord=', Ord(c1), ' ordconst=', Ord(KC));
  WriteLn('i1=', i1);
  WriteLn('f1=', f1:0:1);
end.
