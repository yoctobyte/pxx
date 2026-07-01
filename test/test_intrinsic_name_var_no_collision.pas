program test_intrinsic_name_var_no_collision;
{ A plain variable whose name case-insensitively matches a statement-level
  intrinsic (New/Dispose/ReallocMem/SetLength/Include/Exclude/Str) must not be
  misparsed as that intrinsic on an ordinary statement (assignment, bare read).
  Each of these branches in ParseStatementAST matched on name alone with no
  lookahead, unlike Insert/Delete (which already guarded on a following `(`
  plus FindProc); found via a variable named `str` breaking plain assignment
  while testing feature-inline-loop-var-rio. Fixed by adding the same
  `(FindProc(name) < 0) and (Tokens[TokPos].Kind = tkLParen)` guard everywhere. }
var
  new, dispose, reallocmem, setlength, include, exclude, str: Integer;
begin
  new := 1;         writeln(new);
  dispose := 2;     writeln(dispose);
  reallocmem := 3;  writeln(reallocmem);
  setlength := 4;   writeln(setlength);
  include := 5;     writeln(include);
  exclude := 6;     writeln(exclude);
  str := 7;         writeln(str);
end.
