{ Trampoline ABI proof (feature-lib-pyexec host bridge): call a class's methods
  by NAME through the reflected code pointer, exercising the shapes uforth's
  push/pop/fpush/fpop use — a Variant-by-address param, a Variant hidden-dest
  return, and a Double param/return. If these round-trip, the generic native-call
  trampoline can be built from typed proc-pointer casts (pxx's codegen supplies
  each target's ABI; no hand-rolled asm). }
program test_pyexec_trampoline_abi;

uses typinfo;

type
  TVM = class
    Data: array[0..63] of Int64;
    Top: Integer;
    FData: array[0..63] of Double;
    FTop: Integer;
    procedure Push(const v: Variant);
    function Pop: Variant;
    procedure Fpush(v: Double);
    function Fpop: Double;
  end;

  { thunks matching the reflected methods (Self is the leading Pointer) }
  TPushFn  = procedure(self: Pointer; const v: Variant);
  TPopFn   = function(self: Pointer): Variant;
  TFpushFn = procedure(self: Pointer; v: Double);
  TFpopFn  = function(self: Pointer): Double;

procedure TVM.Push(const v: Variant);
begin
  Data[Top] := v;      { variant -> int64 store }
  Top := Top + 1;
end;

function TVM.Pop: Variant;
begin
  Top := Top - 1;
  Pop := Data[Top];
end;

procedure TVM.Fpush(v: Double);
begin
  FData[FTop] := v;
  FTop := FTop + 1;
end;

function TVM.Fpop: Double;
begin
  FTop := FTop - 1;
  Fpop := FData[FTop];
end;

var
  vm: TVM;
  cls: PClassRTTI;
  pushfn: TPushFn;
  popfn: TPopFn;
  fpushfn: TFpushFn;
  fpopfn: TFpopFn;
  a, b: Variant;
  r: Variant;
  d: Double;

function code(const name: string): Pointer;
var mi: PMethInfo;
begin
  mi := GetMethInfoByName(cls, name);
  if mi = nil then begin writeln('FAIL: no ', name); halt(1); end;
  code := mi^.Code;
end;

begin
  vm := TVM.Create;
  vm.Top := 0; vm.FTop := 0;
  cls := GetInstanceRTTI(vm);
  if cls = nil then begin writeln('FAIL: no rtti'); halt(1); end;

  pushfn  := TPushFn(code('Push'));
  popfn   := TPopFn(code('Pop'));
  fpushfn := TFpushFn(code('Fpush'));
  fpopfn  := TFpopFn(code('Fpop'));

  { push two variants by address, pop them back (Forth SWAP order check) }
  a := 10; b := 32;
  pushfn(Pointer(vm), a);
  pushfn(Pointer(vm), b);
  r := popfn(Pointer(vm));
  writeln('pop1=', Integer(r));          { 32 }
  r := popfn(Pointer(vm));
  writeln('pop2=', Integer(r));          { 10 }

  { float stack }
  fpushfn(Pointer(vm), 2.5);
  fpushfn(Pointer(vm), 4.0);
  d := fpopfn(Pointer(vm));
  writeln('fpop1=', d:0:2);              { 4.00 }
  d := fpopfn(Pointer(vm));
  writeln('fpop2=', d:0:2);              { 2.50 }

  writeln('DONE');
end.
