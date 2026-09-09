{ A BARE method call inside its own class body is checked for arity, like the
  three other spellings of the same call always were.

  `Self.Plain(1.5, 2, 3)`, `c.Plain(1.5, 2, 3)` and a free `Free1(1.5, 2, 3)`
  were all refused. The implicit-Self spelling -- the most common method call
  there is -- was not: FindUMethOverloadAhead is a SELECTOR, so with no
  candidate of the right arity it falls through to the first name match at ANY
  arity, and the hand-rolled argument loop at that site appends whatever it
  parses without consulting the signature.

  Measured on the pre-fix compiler; fpc 3.2.2 refuses all four:

    Plain(1.5, 2, 3)   1 param   ->  x=0.0          every argument lost
    Plain(1.5, 2)      1 param   ->  x=0.0
    Two(7, 8, 9)       2 params  ->  a=8 b=9        Self ate the 7
    Two(7)             2 params  ->  a=369098760    UNINITIALISED memory

  The last row is the reason this is not a diagnostics ticket: it is a garbage
  read with no crash and no message.

  Sibling of test_method_missing_args_report_fail, which pins the same class of
  hole on the QUALIFIED parenless spelling. The must-NOT-break direction lives
  in test_p_a_bare_method_call_arity_still_valid -- exact arity, trailing
  defaults and the variadic `array of const` tail, which passes MORE arguments
  than the signature has ON PURPOSE and reaches this site through the very
  fallback being closed here.
  bug-p-a-bare-method-call-inside-its-own-class-ignores-arity }
program test_p_a_bare_method_call_ignores_arity_fail;
{$mode objfpc}
type
  TC = class
    procedure Plain(x: Double);
    procedure Two(a, b: Integer);
    procedure Go;
  end;

procedure TC.Plain(x: Double);   begin WriteLn('  Plain x=', x:0:1); end;
procedure TC.Two(a, b: Integer); begin WriteLn('  Two a=', a, ' b=', b); end;

procedure TC.Go;
begin
  Plain(1.5, 2, 3);
  Plain(1.5, 2);
  Two(7, 8, 9);
  Two(7);
end;

var c: TC;
begin
  c := TC.Create;
  c.Go;
end.
