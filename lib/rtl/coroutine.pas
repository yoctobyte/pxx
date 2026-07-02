{ SPDX-License-Identifier: Zlib }
unit coroutine;
{ Stackful-generator runtime (PXX-only — FPC has no generators; never used in
  compiler.pas, per the FPC/PXX boundary).

  A generator function marked `; generator;` is compiled into a coroutine body
  (see the generator lowering in parser.inc). The compiler drives it through the
  helpers below; user code only ever writes `for x in Gen(args) do ...`.

  A generator instance is an 80-byte heap block whose layout MUST match the
  CO_OFF_* constants in defs.inc:
    +0  genctx.sp      saved sp of the generator stack
    +8  callerctx.sp   saved sp of the consumer
    +16 current        last yielded value (<= 8 bytes in v1)
    +24 done           0 = live, 1 = exhausted
    +32 stackbase      heap stack base (for FreeMem)
    +40 self           instance ptr; doubles as the rbx-slot handoff in the
                       initial stack frame (CoSwitch pops it into rbx, the body
                       prologue copies rbx -> its hidden self local)
    +48 params         up to 4 Int64-width generator parameters }

interface

function CoAlloc(bodyAddr: Pointer; nparams, p0, p1, p2, p3: Int64): Pointer;
function CoNext(g: Pointer): Boolean;
function CoCurrent(g: Pointer): Int64;
procedure CoFree(g: Pointer);

implementation

const
  CO_STACK = 65536;   { per-generator heap stack (matches CO_STACK_BYTES) }

type
  PW = ^NativeInt;    { pointer-sized machine-word access at an address }

{ Allocate + initialise a generator instance and its heap stack. Builds the
  initial saved-state frame the first CoSwitch-in pops (low->high):
  exc_top, r15, r14, r13, r12, rbx(=self), rbp, return-address(=body). rsp at the
  body's first instruction must be == 8 (mod 16): 16-align the top, back off 8,
  then reserve the 8 saved qwords (64 bytes). }
function CoAlloc(bodyAddr: Pointer; nparams, p0, p1, p2, p3: Int64): Pointer;
var inst, stk, top: Int64;
begin
  inst := Int64(GetMem(80));
  stk  := Int64(GetMem(CO_STACK));

  top := stk + CO_STACK;
  top := top - (top mod 16);   { 16-align down }
  top := top - 8;              { body entry rsp == 8 (mod 16) }
  top := top - 64;             { 8 saved qwords }

  PW(top + 0)^  := 0;                { exc_top -> fresh chain on this stack }
  PW(top + 8)^  := 0;                { r15 }
  PW(top + 16)^ := 0;                { r14 }
  PW(top + 24)^ := 0;                { r13 }
  PW(top + 32)^ := 0;                { r12 }
  PW(top + 40)^ := inst;             { rbx slot -> self handoff }
  PW(top + 48)^ := 0;                { rbp }
  PW(top + 56)^ := Int64(bodyAddr);  { return address -> generator body }

  PW(inst + 0)^  := top;   { genctx.sp }
  PW(inst + 8)^  := 0;     { callerctx.sp }
  PW(inst + 16)^ := 0;     { current }
  PW(inst + 24)^ := 0;     { done }
  PW(inst + 32)^ := stk;   { stackbase }
  PW(inst + 40)^ := inst;  { self }
  if nparams > 0 then PW(inst + 48)^ := p0;
  if nparams > 1 then PW(inst + 56)^ := p1;
  if nparams > 2 then PW(inst + 64)^ := p2;
  if nparams > 3 then PW(inst + 72)^ := p3;

  Result := Pointer(inst);
end;

{ Resume the generator until its next yield (or exhaustion). Returns True while
  a fresh value is available (then CoCurrent reads it), False once exhausted. }
function CoNext(g: Pointer): Boolean;
var inst: Int64;
begin
  inst := Int64(g);
  __pxxcoswitch(Pointer(inst + 8), Pointer(inst + 0));  { consumer -> generator }
  Result := PW(inst + 24)^ = 0;                          { not done }
end;

function CoCurrent(g: Pointer): Int64;
begin
  Result := PW(Int64(g) + 16)^;
end;

{ Free the generator's heap stack and instance. Called once the for-in loop has
  drained the generator (it is suspended on its own stack, which we are not on). }
procedure CoFree(g: Pointer);
var inst: Int64;
begin
  inst := Int64(g);
  FreeMem(Pointer(PW(inst + 32)^));   { heap stack }
  FreeMem(g);                          { instance }
end;

end.
