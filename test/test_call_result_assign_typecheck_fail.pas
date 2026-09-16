{ A string-valued call RESULT stored into an Integer must be REFUSED, in all
  three spellings of a call.

  It compiled silently and stored a POINTER as a number, while the same
  assignment from a string VARIABLE was refused correctly -- so the check
  existed and one spelling of the source never reached it. fpc refuses every row
  here: `Incompatible types: got "AnsiString" expected "LongInt"`.

  ALL THREE CALL KINDS ARE EXERCISED ON PURPOSE. AN_CALL, AN_VIRTUAL_CALL and
  AN_INTF_CALL are one family carrying the Procs[] index in IVal, and ir.inc's
  own comment says "an enumeration that lists only AN_CALL is wrong for every
  override" -- so a fix that reached only the direct call would pass a test that
  only wrote one. The virtual row is dispatched through a base-class reference
  so it cannot be devirtualised into the direct case.

  Positive controls are in test_call_result_assign_typecheck_positive.pas: this
  file says what must be refused, that one says what must NOT be.
  bug-p-a-string-function-result-assigned-to-an-integer-compiles-silently }
program test_call_result_assign_typecheck_fail;
type
  IStr = interface
    function Name: AnsiString;
  end;
  TBase = class
    function Name: AnsiString; virtual;
  end;
  TDerived = class(TBase)
    function Name: AnsiString; override;
  end;
  TImpl = class(TInterfacedObject, IStr)
    function Name: AnsiString;
  end;
function TBase.Name: AnsiString; begin Result := 'base'; end;
function TDerived.Name: AnsiString; begin Result := 'derived'; end;
function TImpl.Name: AnsiString; begin Result := 'impl'; end;
function FStr: AnsiString; begin Result := 'plain'; end;
var n: Integer; b: TBase; it: IStr;
begin
  b := TDerived.Create;
  it := TImpl.Create;
  n := FStr;
  n := b.Name;
  n := it.Name;
  WriteLn(n);
end.
