{ A single-candidate method call must type-check its arguments, like the
  identical free procedure already does.

  Method resolution ranked candidates only when there were 2+ of them:
  FindUMethOverloadAhead short-circuited nCand <= 1 to FindUMethArity, which
  filters on ARITY alone. So the one-method case — most method calls in any
  program — never looked at its argument types, and `c.M(p)` with `p: Pointer`
  and `M(const s: AnsiString)` compiled while the identical free `FreeProc(p)`
  was refused. Two resolvers for one concept, only one finished.
  bug-p-a-single-candidate-method-call-does-not-check-its-argument-types

  fpc 3.2.2 refuses both:
    Incompatible type for arg no. 1: Got "Pointer", expected "AnsiString"

  This file must NOT compile. The positive half — everything the gate must keep
  accepting — is test_method_arg_typecheck_ok.pas beside it. }
{$mode objfpc}
program margfail;
type
  TC = class
    procedure M(const s: AnsiString);
  end;
procedure TC.M(const s: AnsiString); begin WriteLn('M [', s, ']'); end;
var c: TC; p: Pointer;
begin
  c := TC.Create;
  p := nil;
  c.M(p);
end.
