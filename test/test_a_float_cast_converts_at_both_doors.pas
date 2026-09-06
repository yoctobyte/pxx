program test_a_float_cast_converts_at_both_doors;
{ A cast to a float type is a CONVERSION, not a reinterpret of the operand's
  bits — and it has to be that at every door that recognises the type name.

  Three doors recognise a float target: the LEXER KEYWORD arm (`Double`,
  `Single`, `Extended`, `Real`), the USER-ALIAS door (FindTypeAlias) and the
  BUILTIN-NAME door (BuiltinScalarTypeKind, which is reached only by the names
  FPC's System unit spells as identifiers — Currency, TDateTime, ValReal).
  The keyword arm and the alias door converted; the builtin-name door fell
  through to the reinterpret, so `Currency(i)` handed a Double consumer the
  integer's bit pattern while `TCur(i)` on the line below answered the number.

  THE ROWS VARY WHICH DOOR RECOGNISES THE NAME and hold the target kind and the
  operand fixed — that is the axis that selects the arm. fpc 3.2.2 refuses this
  program outright ("Illegal type conversion: LongInt to Currency"), so there is
  no oracle: each row asserts a RELATION between two of our own spellings of one
  cast, which is the assertion shape that needs no second compiler. The
  keyword-spelled rows are the controls — they were right before and must not
  move — and they are on the varied axis rather than in extra rows, so a change
  that broke conversion for everyone would show as a whole column.

  refactor-p-five-dispatch-sites-for-one-named-type-cast }
type
  TCur = Currency; TDt = TDateTime; TVr = ValReal;
  TEx  = Extended; TSg = Single;    TDb = Double;
procedure Row(const lbl: AnsiString; builtinDoor, aliasDoor: Double);
begin
  WriteLn(lbl, builtinDoor:0:4, ' ', aliasDoor:0:4, ' same=',
          builtinDoor = aliasDoor);
end;
var i: LongInt; c: Currency;
begin
  i := 7;
  { identifier-spelled builtins — these are the names that reach the
    builtin-NAME door, and all three were the reinterpret }
  Row('Currency  ', Currency(i),  TCur(i));
  Row('TDateTime ', TDateTime(i), TDt(i));
  Row('ValReal   ', ValReal(i),   TVr(i));
  { keyword-spelled builtins — the controls, answered by the keyword arm }
  Row('Extended  ', Extended(i),  TEx(i));
  Row('Single    ', Single(i),    TSg(i));
  Row('Double    ', Double(i),    TDb(i));
  { and the value stored in its DECLARED type, which is the claim CLAUDE.md
    makes the only one: it was already right, because the assignment coerces,
    and that is exactly why the defect was invisible until the cast was used
    somewhere other than an assignment RHS. }
  c := Currency(i);
  WriteLn('stored    ', c:0:4);
end.
