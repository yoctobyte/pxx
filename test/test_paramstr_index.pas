program test_paramstr_index;
{ Indexing a BUILTIN call's result. `ParamStr(i)[1]` is the row that matters:
  every other string value already indexed (a literal has its own loop, a user
  function and Copy go through the call-result path), and ParamStr is the only
  one with no sysutils twin to shadow it, so it is the only spelling that
  cannot be accidentally satisfied by a `uses` clause.

  Every assertion is a COMPARISON against the same character read the ordinary
  way, never against a literal: ParamStr(0) is the invocation path and differs
  between runs and between compilers, so an expected constant here would be a
  test of the harness's cwd. `agree` is the load-bearing row -- it is the
  ASSIGNMENT-STATEMENT position, which was the one context that used to compile,
  and it compiled to the low byte of the string POINTER (a different wrong
  character on every run) because ParseStatementAST's catch-all `else` ate the
  subscript in silence. The other four rows used to be loud parse errors.
  bug-p-a-builtin-call-result-cannot-be-indexed-inside-parentheses }
var
  cc, c2: Char;
  ss: AnsiString;
  b: Boolean;
begin
  ss := ParamStr(0);
  c2 := ss[1];
  cc := ParamStr(0)[1];
  WriteLn('assign=', cc = c2);
  b := (ParamStr(0)[1] = c2);
  WriteLn('paren=', b);
  WriteLn('arg=', ParamStr(0)[1] = c2);
  b := (1 = 1) and (ParamStr(0)[1] = c2);
  WriteLn('andop=', b);
  if ParamStr(0)[1] = c2 then WriteLn('ifcond=TRUE') else WriteLn('ifcond=FALSE');
  { not just the first character: a wrong-but-constant index would pass every
    row above if the string happened to start and continue with the same byte. }
  WriteLn('second=', ParamStr(0)[2] = ss[2]);
  WriteLn('last=', ParamStr(0)[Length(ss)] = ss[Length(ss)]);
end.
