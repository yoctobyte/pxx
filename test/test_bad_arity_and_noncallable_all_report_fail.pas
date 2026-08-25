program test_bad_arity_and_noncallable_all_report_fail;
{ Three diagnostics that used to be WRONG, not merely early — and each one also
  halted, so a file containing any of them reported nothing else.

    P1;         a routine called with no arguments when it needs one.
                Reported "undefined variable (P1)" over a name that is right
                there in scope. The same misdirection was fixed once for the
                all-defaulted case, whose note reads "the NAME had resolved, the
                ARITY had not" -- this is the arm with no default to fill.

    c.M(1, 2)   too many arguments to a METHOD. Every method-argument loop is
                index-driven -- parse exactly ParamCount, then Expect(')') -- so
                this died as `Expected: ), but got:` pointing at the comma: a
                SYNTAX message for an ARITY mistake. There were SEVEN copies of
                that loop, so the fix is one shared tail (ExpectCallRParen), not
                a seventh guard.

    i(3)        calling a value that is not callable. Expect(':=') reported
                `unexpected token` at a paren, naming neither the mistake nor
                the culprit.

  All three now name the problem AND recover, so this one file reports all four
  mistakes in a single compile. FPC reports the same four lines.

  This test is a `_fail` case: it must NOT compile, and the Makefile asserts the
  exit status and all four messages. }
type
  TC = class
    f: Integer;
    procedure M;
  end;
procedure TC.M; begin end;
procedure P1(x: Integer); begin WriteLn(x); end;
var
  c: TC;
  i: Integer;
begin
  i := 1;
  c := TC.Create;
  P1;
  c.M(1, 2);
  i(3);
  P1(1, 2);
  WriteLn(i);
end.
