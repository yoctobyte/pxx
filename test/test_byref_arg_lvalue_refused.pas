{ The other half of test_byref_arg_lvalue_rule: a genuine `var` parameter still
  REFUSES a non-lvalue, and must, because the callee writes back through the
  caller's storage. FPC refuses it too — `Can't take the address of constant
  expressions` — so this is parity, not strictness.

  This file must FAIL to compile. The Makefile row asserts that and greps for
  the message.

  One shape rather than five, deliberately: after
  bug-a-a-non-lvalue-is-refused-as-an-interface-argument there is exactly ONE
  predicate deciding this (ByRefArgNeedsLvalue), so `var` record / `out` record
  / `var Integer` / `var IFoo` with a constructor or a call result all reach the
  same line. They were checked against FPC when the rule landed and all five
  agree in both directions; pinning one is what a regression would trip on.
  The widening direction — a non-lvalue newly ACCEPTED where it should not be —
  is what this row exists to catch. }
program test_byref_arg_lvalue_refused;
{$mode objfpc}{$H+}

type
  IFoo = interface
    ['{11111111-1111-1111-1111-111111111111}']
    function Tag: Integer;
  end;
  TFoo = class(TInterfacedObject, IFoo)
    function Tag: Integer;
  end;

function TFoo.Tag: Integer; begin Result := 7; end;

procedure TakeVarIface(var a: IFoo);
begin
  a := nil;
end;

begin
  TakeVarIface(TFoo.Create);   { non-lvalue into a var parameter: refused }
end.
