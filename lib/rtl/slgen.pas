{ SPDX-License-Identifier: Zlib }
unit slgen;
{ Stackless-generator runtime (PXX-only — FPC has no generators; never used in
  compiler.pas, per the FPC/PXX boundary).

  A `; generator; stackless;` function is compiled into a state-machine *step*
  function with the ABI `function(self: Pointer): Boolean` (has-next): each call
  advances to the next `yield` (returns True, value in the instance) or to
  exhaustion (returns False). Unlike the stackful backend this needs NO context
  switch and NO heap stack — just a plain heap record — so it runs on every
  target with zero per-target asm. The compiler drives it; user code only ever
  writes `for x in Gen(args) do ...`.

  The instance is a heap block whose layout matches the SL_OFF_* / CO_OFF_*
  constants in defs.inc (CURRENT/DONE offsets are shared with the stackful
  layout so for-in reads the value/done flag identically for either strategy):
    +0   state      resume point; 0 = not yet started
    +16  current    last yielded value (<= 1 machine word in v1)
    +24  done       0 = live, 1 = exhausted
    +48  slots      persistent params then locals, one machine word each }

interface

function SlAlloc(instSize, nparams, p0, p1, p2, p3: Int64): Pointer;
function SlGet(g: Pointer; off: Int64): Int64;
procedure SlSet(g: Pointer; off, val: Int64);
function SlCurrent(g: Pointer): Int64;
procedure SlFree(g: Pointer);

implementation

const
  SL_SLOTS = 48;   { = SL_OFF_SLOTS }

type
  PW = ^NativeInt;   { pointer-sized machine-word access at an address }
  PB = ^Byte;

{ Allocate + zero a stackless-generator instance, then store the generator
  arguments into the first persistent slots (where the step function's restore
  prologue expects its declared params). }
function SlAlloc(instSize, nparams, p0, p1, p2, p3: Int64): Pointer;
var inst, i: Int64;
begin
  inst := Int64(GetMem(instSize));
  i := 0;
  while i < instSize do begin PB(inst + i)^ := 0; i := i + 1; end;
  if nparams > 0 then PW(inst + SL_SLOTS + 0)^  := p0;
  if nparams > 1 then PW(inst + SL_SLOTS + 8)^  := p1;
  if nparams > 2 then PW(inst + SL_SLOTS + 16)^ := p2;
  if nparams > 3 then PW(inst + SL_SLOTS + 24)^ := p3;
  Result := Pointer(inst);
end;

function SlGet(g: Pointer; off: Int64): Int64;
begin
  Result := PW(Int64(g) + off)^;
end;

procedure SlSet(g: Pointer; off, val: Int64);
begin
  PW(Int64(g) + off)^ := val;
end;

function SlCurrent(g: Pointer): Int64;
begin
  Result := PW(Int64(g) + 16)^;   { = SL_OFF_CURRENT }
end;

procedure SlFree(g: Pointer);
begin
  FreeMem(g);
end;

end.
