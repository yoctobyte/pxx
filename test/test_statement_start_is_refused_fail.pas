program test_statement_start_is_refused_fail;
{ A statement cannot START with a postfix or a closing token, and until this
  was checked ParseStatementAST's catch-all `else` skipped to the `;` in
  SILENCE -- so `[1];`, `^;`, `.Foo;`, `);` and `,;` each compiled clean, exit 0.

  The cost was never the garbage program nobody writes. This arm is the LANDING
  SITE for any construct another arm returns from with tokens still pending, so
  it converts that arm's bug into a silently discarded statement. Two measured:
  `ParamStr(0)[1]` lost its subscript here and stored the low byte of a POINTER,
  and `F1(1) := 3` (the guard below this one) emitted the call and dropped the
  store. The second was fixed by naming that one construct; this fixes the
  mechanism, which is what normalise-dont-special-case.md asks for.

  Its first run against real source found THREE dead statements in shipped RTL:
  orphaned argument tails of debug WriteLn( heads deleted in 1f8bb3e75, sitting
  inside compiler/builtin/pylib.pas for five weeks, inert and invisible.

  Error and not ErrorRecover, so this halts at the FIRST one -- a syntax failure
  leaves the parser's position meaningless, which is the line ErrorRecover's own
  contract draws. That is why this file carries exactly one offending statement;
  its siblings are asserted by the Makefile recipe compiling them separately.
  bug-p-a-statement-that-cannot-start-with-this-token-is-silently-skipped }
var ii: Integer;
begin
  ii := 1;
  [1];
  WriteLn('unreachable ', ii);
end.
