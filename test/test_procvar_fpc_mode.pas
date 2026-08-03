program test_procvar_fpc_mode;
{$MODE OBJFPC}
{ The OTHER half of the procvar pair. In FPC's own modes a bare procedural
  variable in a value context is NOT called — it yields the ADDRESS — and only
  {$MODE DELPHI} calls it. This project targets FPC compliance, so this file is
  the one that guards the default, and test_procvar_value_context.pas asserts
  the Delphi answers.

  Every expectation measured from FPC 3.2.2 with -Mobjfpc, the same program
  compiled in all three modes:

    context                       FPC / OBJFPC     DELPHI
    p := fp      (p: Pointer)     address          CALL
    PtrUInt(fp)  (cast)           address          CALL
    Takes(fp)    (Pointer param)  address          CALL
    fp = nil / fp = fp2           address compare  CALL both
    Takes(fp)    (procvar param)  address          address
    Assigned(fp), @fp             address          address

  This was a real regression, not a hypothetical: the first cut of the
  Delphi auto-call fired in every mode, so `p := fp` under {$MODE FPC} returned
  the call result where FPC returns the address.
  bug-pascal-procvar-value-context-outside-assignment }

type
  TF = function: Pointer; cdecl;

var
  fp, fp2: TF;
  p: Pointer;
  rc: Integer;
  ptrParamWasCalled, pvParamWasCalled: Boolean;

{ Returns nil, so "was it called?" is unambiguous: a call yields nil while the
  procvar's own address never is. }
function ImplNil: Pointer; cdecl;
begin ImplNil := nil; end;
function ImplNil2: Pointer; cdecl;
begin ImplNil2 := nil; end;

procedure CheckPtrParam(q: Pointer);
begin ptrParamWasCalled := q = nil; end;

procedure CheckProcVarParam(f: TF);
begin pvParamWasCalled := not Assigned(f); end;

begin
  rc := 0;
  fp := @ImplNil;
  fp2 := @ImplNil2;

  { Assignment to a non-procvar: the ADDRESS, not the call result. }
  p := fp;
  if p = nil then rc := 1;

  { Cast: the address. }
  if PtrUInt(fp) = 0 then rc := 2;

  { Argument to a Pointer parameter: the address. }
  CheckPtrParam(fp);
  if ptrParamWasCalled then rc := 3;

  { Argument to a proc-typed parameter: the address, in every mode. }
  CheckProcVarParam(fp);
  if pvParamWasCalled then rc := 4;

  { Comparison compares ADDRESSES here, so a non-nil fp whose call returns nil
    is NOT equal to nil — the exact opposite of Delphi mode. }
  if fp = nil then rc := 5;

  { Two distinct functions returning the same value are DIFFERENT addresses. }
  if fp = fp2 then rc := 6;

  { Assigned() and @ are address-based in every mode. }
  if not Assigned(fp) then rc := 7;
  if @fp = nil then rc := 8;

  { A procvar-to-procvar copy is a pointer copy, and the copy still calls. }
  fp2 := fp;
  if not Assigned(fp2) then rc := 9;
  if fp2() <> nil then rc := 10;

  { Explicit parens always call, in every mode. }
  if fp() <> nil then rc := 11;

  if rc = 0 then writeln('procvar-fpc-mode OK')
  else writeln('procvar-fpc-mode FAIL ', rc);
end.
