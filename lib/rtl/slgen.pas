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

function SlNew(instSize: Int64): Pointer;
function SlGet(g: Pointer; off: Int64): Int64;
procedure SlSet(g: Pointer; off, val: Int64);
function SlCurrent(g: Pointer): Int64;
procedure SlFree(g: Pointer);
procedure SlBlob(g: Pointer; off: Int64; src: Pointer; nbytes: Int64);
procedure SlUnblob(g: Pointer; off: Int64; dst: Pointer; nbytes: Int64);

implementation

const
  SL_SLOTS = 48;   { = SL_OFF_SLOTS }

type
  PW = ^NativeInt;   { pointer-sized machine-word access at an address }
  PB = ^Byte;

{ Allocate + zero a stackless-generator instance. The for-in desugar stores
  each provided generator argument with its own SlSet(g, SL_SLOTS + 8*k, ak)
  afterwards — the old packed SlAlloc(instSize, nparams, p0..p3) had 6 Int64
  params = 12 argument words, over the riscv32 backend's 8-word call limit. }
function SlNew(instSize: Int64): Pointer;
var inst, i: Int64;
begin
  inst := Int64(GetMem(instSize));
  i := 0;
  while i < instSize do begin PB(inst + i)^ := 0; i := i + 1; end;
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

{ Byte-copy a record (or any blob) INTO the instance at `off` — checkpoints a
  record local / the yielded record CURRENT value across a suspension. Byte
  loop: portable to every target, no Move/alignment assumptions. }
procedure SlBlob(g: Pointer; off: Int64; src: Pointer; nbytes: Int64);
var i: Int64;
begin
  i := 0;
  while i < nbytes do
  begin
    PB(Int64(g) + off + i)^ := PB(Int64(src) + i)^;
    i := i + 1;
  end;
end;

{ Byte-copy a blob OUT of the instance at `off` — restores a record local into
  its stack slot on step re-entry. }
procedure SlUnblob(g: Pointer; off: Int64; dst: Pointer; nbytes: Int64);
var i: Int64;
begin
  i := 0;
  while i < nbytes do
  begin
    PB(Int64(dst) + i)^ := PB(Int64(g) + off + i)^;
    i := i + 1;
  end;
end;

end.
