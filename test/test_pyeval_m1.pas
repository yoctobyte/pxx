{ pyeval M1 driver (feature-lib-pyexec engine 1). Runs the pure-stack PYTHON
  corpus idioms — SWAP/OVER/ROT, arithmetic, bit ops, shifts, ternary min/max,
  floordiv/mod, augassign — through EvalPyStmts against a stub VM whose
  push/pop/fpush/fpop are reached BY NAME through the reflection trampoline.
  No uforth needed; the block sources are inlined verbatim from CORE/MATH. }
program test_pyeval_m1;

uses pylib, typinfo, pyeval;

type
  PVRec = ^TVRec;
  TVRec = record VType: Int64; Payload: Int64; end;

  TVM = class
    Data: array[0..255] of Int64;
    Top: Integer;
    FData: array[0..63] of Double;
    FTop: Integer;
    procedure Push(const v: Variant);
    function Pop: Variant;
    procedure Fpush(v: Double);
    function Fpop: Double;
  end;

procedure TVM.Push(const v: Variant);
begin
  Data[Top] := PVRec(@v)^.Payload;   { stack holds raw int cells }
  Top := Top + 1;
end;

function TVM.Pop: Variant;
begin
  Top := Top - 1;
  PVRec(@Result)^.VType := 2;        { VT_INT64 }
  PVRec(@Result)^.Payload := Data[Top];
end;

procedure TVM.Fpush(v: Double);
begin
  FData[FTop] := v; FTop := FTop + 1;
end;

function TVM.Fpop: Double;
begin
  FTop := FTop - 1; Fpop := FData[FTop];
end;

var
  vm: TVM;
  g: TPyDict;
  vmv: Variant;
  fails: Integer;

{ push a raw int cell onto the vm stack }
procedure InPush(n: Int64);
var v: Variant;
begin
  PVRec(@v)^.VType := 2; PVRec(@v)^.Payload := n;
  vm.Push(v);
end;

function OutPop: Int64;
var v: Variant;
begin
  v := vm.Pop;
  OutPop := PVRec(@v)^.Payload;
end;

procedure Run(const src: AnsiString);
var l: TPyDict;
begin
  l := TPyDict.Create;
  EvalPyStmts(src, g, l);
end;

procedure Check(const label: AnsiString; got, want: Int64);
begin
  if got = want then
    writeln('ok   ', label, ' = ', got)
  else
  begin
    writeln('FAIL ', label, ' got ', got, ' want ', want);
    fails := fails + 1;
  end;
end;

begin
  fails := 0;
  vm := TVM.Create;
  vm.Top := 0; vm.FTop := 0;

  g := TPyDict.Create;
  PVRec(@vmv)^.VType := 7;                    { VT_OBJECT }
  PVRec(@vmv)^.Payload := Int64(Pointer(vm));
  g.store('vm', vmv);

  { SWAP: b=pop;a=pop;push(b);push(a)  — stack 10,32 -> pop 10 then 32 }
  vm.Top := 0; InPush(10); InPush(32);
  Run('b = pop(); a = pop(); push(b); push(a)');
  Check('SWAP top', OutPop, 10);
  Check('SWAP next', OutPop, 32);

  { OVER: b,a -> a,b,a ; stack 1,2 -> after: 1,2,1 top=1 }
  vm.Top := 0; InPush(1); InPush(2);
  Run('b = pop(); a = pop(); push(a); push(b); push(a)');
  Check('OVER top', OutPop, 1);
  Check('OVER mid', OutPop, 2);
  Check('OVER bot', OutPop, 1);

  { ROT: c,b,a -> b,c,a ; stack 1,2,3 (a=3,b=2,c=1?) push order }
  vm.Top := 0; InPush(1); InPush(2); InPush(3);
  Run('c = pop(); b = pop(); a = pop(); push(b); push(c); push(a)');
  Check('ROT top', OutPop, 1);   { a }
  Check('ROT mid', OutPop, 3);   { c }
  Check('ROT bot', OutPop, 2);   { b }

  { AND }
  vm.Top := 0; InPush($F0); InPush($3C);
  Run('b = pop(); a = pop(); push(a & b)');
  Check('AND', OutPop, $30);

  { OR }
  vm.Top := 0; InPush($F0); InPush($0C);
  Run('b = pop(); a = pop(); push(a | b)');
  Check('OR', OutPop, $FC);

  { XOR: push(b ^ a) }
  vm.Top := 0; InPush($FF); InPush($0F);
  Run('b = pop(); a = pop(); push(b ^ a)');
  Check('XOR', OutPop, $F0);

  { INVERT: push(~pop()) }
  vm.Top := 0; InPush(0);
  Run('push(~pop())');
  Check('INVERT', OutPop, -1);

  { arithmetic shift right (2/): push(pop() >> 1) on negative }
  vm.Top := 0; InPush(-8);
  Run('push(pop() >> 1)');
  Check('2/ neg', OutPop, -4);

  { LSHIFT: n=int(pop()); push(pop() << n) — stack a,n }
  vm.Top := 0; InPush(1); InPush(4);
  Run('n = int(pop()); push(pop() << n)');
  Check('LSHIFT', OutPop, 16);

  { ABS ternary: a=pop; push(a if a>=0 else -a) }
  vm.Top := 0; InPush(-42);
  Run('a = pop(); push(a if a >= 0 else -a)');
  Check('ABS', OutPop, 42);

  { MAX ternary: b,a -> push(a if a>b else b) }
  vm.Top := 0; InPush(7); InPush(3);
  Run('b = pop(); a = pop(); push(a if a > b else b)');
  Check('MAX', OutPop, 7);

  { signed FM/MOD floordiv+mod: /MOD -> push(rem); push(quot) with Python floor }
  vm.Top := 0; InPush(-7); InPush(2);
  Run('b = pop(); a = pop(); q = -(-a // b) if (a < 0) != (b < 0) else a // b; push(a - q * b); push(q)');
  Check('SM/REM quot', OutPop, -3);   { symmetric trunc: -7/2 -> -3 }
  Check('SM/REM rem', OutPop, -1);    { -7 - (-3*2) = -1 }

  { floordiv pure (Python floor): -7 // 2 = -4 }
  vm.Top := 0; InPush(-7); InPush(2);
  Run('b = pop(); a = pop(); push(a // b)');
  Check('floordiv', OutPop, -4);

  { augassign chain }
  vm.Top := 0; InPush(5);
  Run('x = pop(); x += 3; x *= 2; x -= 1; push(x)');
  Check('augassign', OutPop, 15);

  { comparison producing 0/-1 flag (Forth true = -1): push(-1 if a < b else 0) }
  vm.Top := 0; InPush(3); InPush(9);
  Run('b = pop(); a = pop(); push(-1 if a < b else 0)');
  Check('less flag', OutPop, -1);

  { NOTE — masked unsigned compare (U<) is DEFERRED to the bignum tail: Python's
    `x & 0xFFFFFFFFFFFFFFFF` yields the arbitrary-precision unsigned value
    (2^64-1 for -1), but M1 models ints as Int64 so the mask leaves -1 unchanged.
    The double-cell MATH words (UM*, M*/, D< …) need the same bignum semantics and
    are out of M1 scope. Verify masking is at least a no-op on a small value: }
  vm.Top := 0; InPush(5);
  Run('a = int(pop()) & 0xFFFFFFFFFFFFFFFF; push(a)');
  Check('mask small (no bignum)', OutPop, 5);

  { float stack round-trip via fpush/fpop bridge }
  vm.FTop := 0;
  Run('fpush(2.5)');
  Check('fpop', Trunc(vm.Fpop * 10), 25);

  writeln;
  if fails = 0 then writeln('ALL PASS')
  else writeln(fails, ' FAILURES');
  if fails <> 0 then Halt(1);
end.
