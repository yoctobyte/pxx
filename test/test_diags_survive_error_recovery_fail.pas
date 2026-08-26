{ %fail }
{ Every dialect rule below is reported even though line 27 already produced a
  RECOVERED diagnostic before any of them.

  That was not true until this test existed. `519fa45a0` put `if ErrCount > 0
  then Exit` at the top of CompileAST -- correct, do not lower a failed AST --
  and thereby made every check that lived ONLY in IR lowering unreachable the
  moment anything earlier in the file was recovered. A recovered error is
  exactly the case where compilation continues in order to report more, so the
  result was "report all the errors the parser happens to own", silently.

  The checks below are Pascal DIALECT rules that were squatting in the shared
  IR (devdocs/dev/the-substrate-is-ast-and-ir-not-the-parser.md); they now run
  where the frontend can see them, and the lowering keeps its own call as the
  backstop for case/operator nodes no Pascal parse built.

  The shape is the point: a lowering-owned refusal asserted AFTER an earlier
  recovered one. Nothing covered it before -- the test that caught the first
  instance caught it by accident.
  bug-a-error-recovery-silences-every-lowering-only-diagnostic }
program test_diags_survive_error_recovery_fail;
type
  TR = record x: Integer; end;
var
  r, q: TR; d, e: array of Integer; n: Integer; s: string;
begin
  n := undefinedthing;              { recovered, parser-owned -- the gate }
  n := r + q;                       { no operator overload for record operands }
  d := d - e;                       { arithmetic on dynamic arrays }
  case n of
    'ab': WriteLn('x');             { string label, ordinal selector }
  end;
  s := 'q';
  case s of
    7: WriteLn('y');                { ordinal label, string selector }
  end;
  case n of
    9..3: WriteLn('z');             { inverted range -- --strict-case only }
    1: WriteLn('a');
    1: WriteLn('b');                { duplicate -- --strict-case only }
  end;
end.
