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

  COVERED here: the assignment context (`Result := fp`, `v := fp`), which is
  the reported bug and the Synapse shape. Other value contexts — a procvar
  inside a cast or a call argument, e.g. `Int64(fp)` — are NOT yet called; see
  bug-pascal-procvar-value-context-outside-assignment. }

type
  TF = function: Pointer; cdecl;
  TG = function(x: Integer): Pointer; cdecl;

var
  fp, fp2: TF;
  gp, gp2: TG;
  magic, addrOfImpl, viaAssign: Pointer;
  rc: Integer;

function Impl: Pointer; cdecl;
begin Impl := magic; end;

function ImplG(x: Integer): Pointer; cdecl;
begin ImplG := Pointer(Int64(x)); end;

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

  if rc = 0 then writeln('procvar-value-context OK')
  else writeln('procvar-value-context FAIL ', rc);
end.
