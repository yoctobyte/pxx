program test_sweep_thunk_preserves_stack_alignment;
{ THE GUARD FOR EmitSweepThunkStackAdjust, WHICH HAD NONE.

  The sweep thunk compensates for the return address a `call` pushes, so the
  sweep's own calls see the alignment the INLINE sweep saw: sub rsp,8 on
  x86-64, sub esp,12 on i386 (a call pushes 8 and 4 respectively -- the
  constant is per-target and must not be copied between them).

  Emitting the WRONG constant broke no test in this tree. Measured 2026-09-07:
  with the x86-64 value emitted on i386, test_managed_sweep_thunk still printed
  its exact expected output and an identical allocation census, natively, with
  exceptions. Three reasons nothing saw it -- the sweep's callees are
  pxx-internal, neither backend emits a memory-operand movaps, and the external
  call path re-aligns for itself. So the constant was correct by contract and
  guarded by nothing.

  THIS IS THE PATH THAT REACHES IT WITHOUT INLINE ASM. An interface local's
  release goes SXR_INTF -> PXXIntfRelease -> _Release -> Destroy, which is USER
  code, so the destructor's frame inherits the alignment the sweep ran with.
  Taking the address of a local reads that alignment.

  IT ASSERTS A RELATION, NOT A VALUE: every return in ONE body must leave the
  destructor's frame equally aligned. A body's FIRST return is always emitted
  inline and the rest CALL the thunk, so one procedure with three returns
  already contains both arms -- min and max of the residue over all of them
  must be equal. No absolute expected value appears, so there is nothing for a
  do-nothing default to collide with, and the row needs no per-target constant.

  THE FIRST VERSION OF THIS TEST WAS BLIND AND THE POSITIVE CONTROL IS WHAT
  CAUGHT IT. It compared a three-return procedure against a one-return one and
  read `gResidue` after each loop -- but the loop ended at i=30, 30 mod 3 = 0
  selected the FIRST return, and the first return is inline. Both readings came
  from inline sweeps, so they agreed trivially and the test printed OK against
  a deliberately broken compiler on both targets. Sampling the last iteration
  meant the arm under test was never the arm measured. Min-and-max over every
  call removes the dependence on which path the final iteration happened to
  take.

  Positive control, re-run after that fix: with the x86-64 compensation emitted
  as 16 instead of 8, and with the i386 one as 8 instead of 12, this test FAILS
  on the respective target and passes with the correct constants. }
{$mode objfpc}
type
  IProbe = interface function Tag: LongInt; end;
  TProbe = class(TInterfacedObject, IProbe)
    function Tag: LongInt;
    destructor Destroy; override;
  end;
var
  gLo, gHi: PtrUInt;
  gSeen: LongInt;

function TProbe.Tag: LongInt; begin Result := 1; end;

destructor TProbe.Destroy;
var marker: LongInt; gR: PtrUInt;
begin
  marker := 0;
  gR := PtrUInt(@marker) and 15;
  if (gSeen = 0) or (gR < gLo) then gLo := gR;
  if (gSeen = 0) or (gR > gHi) then gHi := gR;
  gSeen := gSeen + 1;
  inherited Destroy;
end;

{ Three returns and four releasable slots: the thunk is placed and every
  return after the first CALLs it. }
function Thunked(n: LongInt): AnsiString;
var p: IProbe; a, b, c: AnsiString;
begin
  p := TProbe.Create;
  p.Tag;
  a := 'aa'; b := 'bb'; c := 'cc';
  a := a + b;
  if (n mod 3) = 0 then begin Thunked := a; Exit; end;
  if (n mod 3) = 1 then begin Thunked := c; Exit; end;
  Thunked := a + c;
end;

var i: LongInt; s: AnsiString;
begin
  gSeen := 0; gLo := 0; gHi := 0;
  { 1..30 walks all three returns ten times each: the inline first return and
    the two that call the thunk. }
  for i := 1 to 30 do s := Thunked(i);
  if gSeen <> 30 then
    WriteLn('ALIGN NOT-REACHED seen=', gSeen)     { the destructor must actually run }
  else if gLo = gHi then
    WriteLn('ALIGN OK')
  else
    WriteLn('ALIGN MISMATCH lo=', gLo, ' hi=', gHi);
end.
