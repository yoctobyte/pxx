{ MUST NOT COMPILE. Empty parens at a call to the enclosing class's own method,
  spelled WITHOUT a receiver, against a REQUIRED parameter.

  `Desc();` was accepted here and the callee read whatever was in the argument
  slot -- `Length(a)` answered 8 against `const a: array of const`, with no
  diagnostic. The qualified spelling `Self.Desc()` in the same program refused
  it correctly, and fpc 3.2.2 refuses the bare one as well ("Wrong number of
  parameters specified for call to \"Desc\""), so this is not us accepting more
  than fpc -- the value is simply garbage.

  BOTH SPELLINGS ARE ASSERTED, on adjacent lines, because the defect was
  exactly that they disagreed. A file testing only the bare one would go green
  the day someone breaks the qualified one instead.

  THE ASSERTION IS THE LINE NUMBER, AND THAT IS NOT PEDANTRY. `Error` HALTS,
  so exactly one diagnostic ever prints from this file -- and the PINNED
  compiler refuses it too, at line 44, the QUALIFIED call. A row asserting only
  "refused" or only the message text is green on the pin and green on HEAD and
  measures nothing; the broken build reports 44 and the fixed one reports 43,
  because the bare call is now caught FIRST. That is the whole defect, stated
  as the one number the two builds cannot agree on.

  The all-defaulted twin is in test_p_a_bare_variadic_method_call.pas (`Def`,
  which prints 34 and matches fpc): the condition is whether the first
  UNSUPPLIED parameter has a declared default, never the arity.

  bug-p-empty-parens-at-a-bare-method-call-reads-a-garbage-argument }
{$mode objfpc}
program test_p_empty_parens_at_a_bare_method_call_fail;
type
  TC = class
    procedure Desc(const a: array of const);
    procedure Go;
  end;

procedure TC.Desc(const a: array of const);
begin
  WriteLn('n=', Length(a));
end;

procedure TC.Go;
begin
  Desc();
  Self.Desc();
end;

var c: TC;
begin
  c := TC.Create;
  c.Go;
end.
