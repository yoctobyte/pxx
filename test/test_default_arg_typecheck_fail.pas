{ A WRONGLY TYPED argument must stay wrongly typed when a trailing parameter
  carries a default.

  Until 2026-09-17 it did not. TryFillTrailingDefaults -- the fallback that
  supplies omitted trailing defaults -- chose its candidate on NAME and ARITY
  alone, and it runs exactly where the ordinary match has already refused. So
  every call below compiled: the argument was passed raw and read as the
  parameter's type. `P(rec)` against `const c: AnsiString` printed
  Length(c) = 17297991344808736; `P(s)` against `c: Integer` printed the
  string's address. fpc 3.2.2 refuses all of them
  ("Incompatible type for arg no. 1").

  THE CONTROL IS THE PAIR, NOT THE ROW. Each shape here is refused by pxx
  already when the trailing argument is WRITTEN OUT -- that spelling never
  reached this fallback. So the defect was never "the check is missing", it was
  "one of the two spellings of the same call was wired to it", and a row on its
  own cannot show that. The written-out twins live in the positive file's
  sibling assertions and in this file's own comments.

  ORDERED LAST ON PURPOSE (CLAUDE.md): the last two cases put the bad argument
  in position 2 and 3, behind good ones. A gate that checked only argument 0
  passes both.

  Expected: pascal26 exits 1, names every line, and writes no binary. }
program test_default_arg_typecheck_fail;

type TR = record a: Integer; end;

function TakesStr(const c: AnsiString; k: Integer = 0): Integer;
begin TakesStr := Length(c) + k; end;

function TakesInt(c: Integer; k: Integer = 0): Integer;
begin TakesInt := c + k; end;

function TwoThenBad(a: Integer; const c: AnsiString; k: Integer = 0): Integer;
begin TwoThenBad := a + Length(c) + k; end;

function ThreeThenBad(a: Integer; b: Integer; c: Integer; k: Integer = 0): Integer;
begin ThreeThenBad := a + b + c + k; end;

var r: TR; s: AnsiString;
begin
  r.a := 1; s := 'hi';
  WriteLn(TakesStr(r));
  WriteLn(TakesInt(s));
  WriteLn(TwoThenBad(1, r));
  WriteLn(ThreeThenBad(1, 2, s));
end.
