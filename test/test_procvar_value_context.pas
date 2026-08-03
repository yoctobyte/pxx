program test_procvar_value_context;
{$MODE DELPHI}
{ A procedural VARIABLE in a value context is CALLED (FPC/Delphi). Taking its
  address is what `@fp` is for. `fp()` with explicit parens was already right,
  so the two spellings disagreed and the wrong one is what real Delphi code
  writes — every dynamic-binding layer is "load a function pointer, wrap it in
  a function that calls it".

  The wrong value was a VALID POINTER, so nothing errored: Synapse passed
  `@TLS_method` to SSL_CTX_new and libssl died far away dereferencing it as a
  method table.

  Expectations measured from FPC 3.2.2 in Delphi mode.
  bug-pascal-procvar-in-value-context-takes-address-instead-of-calling

  DELPHI MODE ONLY. FPC and OBJFPC mode pass the ADDRESS in every context below
  — measured, not assumed — and this project targets FPC, so the auto-call is
  gated on the mode. test_procvar_fpc_mode.pas is the other half of that pair
  and asserts the opposite answers. }

type
  TF = function: Pointer; cdecl;
  TG = function(x: Integer): Pointer; cdecl;

var
  fp, fp2, fpNil, fpA, fpB: TF;
  gp, gp2: TG;
  magic, addrOfImpl, viaAssign: Pointer;
  rc: Integer;
  ptrParamGotResult, pvParamWasCalled: Boolean;

function Impl: Pointer; cdecl;
begin Impl := magic; end;

function ImplG(x: Integer): Pointer; cdecl;
begin ImplG := Pointer(Int64(x)); end;

function ImplNil: Pointer; cdecl;
begin ImplNil := nil; end;

{ Two DISTINCT functions returning the SAME value: comparing addresses and
  comparing results then give opposite answers, so the probe is unambiguous. }
function ImplA: Pointer; cdecl;
begin ImplA := magic; end;
function ImplB: Pointer; cdecl;
begin ImplB := magic; end;

{ A Pointer parameter WANTS a value, so a bare procvar argument is called. }
procedure CheckPtrParam(q: Pointer);
begin ptrParamGotResult := Int64(q) = Int64($DEADBEEF); end;

{ A proc-typed parameter wants the procvar ITSELF, so it is passed untouched —
  the callee can still call it, and Assigned() proves it arrived as a pointer. }
procedure CheckProcVarParam(f: TF);
begin pvParamWasCalled := not Assigned(f); end;

{ The exact shape from Synapse's ssl_openssl3_lib.pas:613. }
function ViaBareName: Pointer;
begin
  if Assigned(fp) then Result := fp else Result := nil;
end;

begin
  rc := 0;
  magic := Pointer(Int64($DEADBEEF));
  fp := @Impl;
  gp := @ImplG;
  addrOfImpl := @Impl;

  { The bug: a bare procvar as a function RESULT was the address, not the call. }
  if Int64(ViaBareName) <> Int64($DEADBEEF) then rc := 1;

  { Same rule for a plain variable assignment. }
  viaAssign := fp;
  if Int64(viaAssign) <> Int64($DEADBEEF) then rc := 2;

  { `fp()` agrees with the bare name — the two spellings must not diverge. }
  viaAssign := fp();
  if Int64(viaAssign) <> Int64($DEADBEEF) then rc := 3;

  { procvar := procvar still copies the POINTER; it must not be called. }
  fp2 := fp;
  if Int64(@fp2) = 0 then rc := 4;
  if Int64(fp2()) <> Int64($DEADBEEF) then rc := 5;   { fp2 really holds Impl }

  { `@fp` still yields an address, and Assigned() does not call. }
  if Int64(addrOfImpl) = 0 then rc := 6;
  if not Assigned(fp) then rc := 7;

  { A signature WITH parameters is never called from a bare name — there are no
    arguments to supply — so this stays an ordinary pointer copy. (FPC rejects
    `Pointer(gp)` outright: it reads that as a CALL and reports the wrong
    parameter count, which is its own confirmation of the rule.) }
  gp2 := gp;
  if Int64(gp2(5)) <> 5 then rc := 8;
  if Int64(gp(5)) <> 5 then rc := 9;

  { ---- value contexts beyond the assignment RHS ---- }

  { A CAST takes the call's RESULT. `@fp` is how you take the address. }
  if Int64(PtrUInt(fp)) <> Int64($DEADBEEF) then rc := 10;

  { An ARGUMENT is called when the parameter wants a value... }
  fpNil := @ImplNil;
  CheckPtrParam(fp);
  if not ptrParamGotResult then rc := 11;

  { ...and passed as-is when the parameter is itself proc-typed. }
  CheckProcVarParam(fpNil);
  if pvParamWasCalled then rc := 12;

  { A COMPARISON compares call RESULTS in Delphi mode — `fp = nil` is TRUE when
    fp() RETURNS nil, even though fp itself is not nil. Address comparison is
    spelled `@fp`. }
  if not (fpNil = nil) then rc := 13;
  if Int64(@fpNil) = 0 then rc := 14;

  { Two DISTINCT functions returning the same value compare EQUAL, because it is
    the results being compared, not the addresses. }
  fpA := @ImplA; fpB := @ImplB;
  if not (fpA = fpB) then rc := 15;

  { Assigned() is the exception: it tests the POINTER, in every mode. It
    desugars to the same `<> nil` node as the comparison above, so this row is
    what keeps the two apart. }
  if not Assigned(fpNil) then rc := 16;

  if rc = 0 then writeln('procvar-value-context OK')
  else writeln('procvar-value-context FAIL ', rc);
end.
