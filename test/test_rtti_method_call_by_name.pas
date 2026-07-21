{ Method invoke-by-name over ANY method (not just published), with the signature
  the generic native-call trampoline needs: arity (incl. Self), return kind, and
  the per-param type kinds. Calls the reflected code via a typed proc-pointer
  cast — the fixed-signature form the trampoline generalizes.
  (feature-lib-pyexec host bridge / method side.) }
program test_rtti_method_call_by_name;

uses typinfo;

type
  TAdder = class
    Base: Int64;
    function Add(x: Int64): Int64;
    procedure Bump;
  end;

  TAddFn  = function(self: Pointer; x: Int64): Int64;
  TBumpFn = procedure(self: Pointer);
  PInt64Arr = ^Int64;

function TAdder.Add(x: Int64): Int64;
begin
  Add := Base + x;
end;

procedure TAdder.Bump;
begin
  Base := Base + 1;
end;

var
  a: TAdder;
  cls: PClassRTTI;
  mi: PMethInfo;
  pk: PInt64Arr;
  r: Int64;
  addfn: TAddFn;
  bumpfn: TBumpFn;
begin
  a := TAdder.Create;
  a.Base := 100;
  cls := GetInstanceRTTI(a);
  if cls = nil then begin writeln('FAIL: no rtti'); halt(1); end;

  mi := GetMethInfoByName(cls, 'Add');
  if mi = nil then begin writeln('FAIL: no Add'); halt(1); end;
  writeln('Add arity=', mi^.Arity, ' retKind=', mi^.RetKind);
  pk := PInt64Arr(mi^.ParamKinds);
  if pk <> nil then
    writeln('Add param0kind=', pk^, ' param1kind=', PInt64Arr(PtrUInt(pk) + 8)^);

  { call the reflected code: Self then the Int64 arg }
  addfn := TAddFn(mi^.Code);
  r := addfn(Pointer(a), 42);
  writeln('Add(42)=', r);

  mi := GetMethInfoByName(cls, 'Bump');
  if mi = nil then begin writeln('FAIL: no Bump'); halt(1); end;
  writeln('Bump arity=', mi^.Arity, ' retKind=', mi^.RetKind);
  bumpfn := TBumpFn(mi^.Code);
  bumpfn(Pointer(a));
  writeln('Base(after Bump)=', a.Base);

  if GetMethInfoByName(cls, 'Nope') = nil then writeln('absent=ok')
  else writeln('FAIL: phantom method');

  writeln('DONE');
end.
