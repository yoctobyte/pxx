{ Zero-initialisation of managed LOCALS on wasm32, tested on a DIRTY frame.

  Every bug this guards against is invisible on a clean stack, which is the
  whole difficulty: a slot that happens to hold zero behaves exactly like a
  slot that was zeroed, so a test that just declares a local and uses it passes
  either way. `Dirtier` exists to make the shadow stack hostile — a deep
  recursion writing recognisable non-zero words into a frame the routines below
  then reuse. Without it this slice passes against a compiler with the zero-init
  pass DELETED; with it, that build traps.

  Measured, both directions, on 2026-08-29: with the pass removed, `Victim`
  dies with `memory access out of bounds` — it releases the dirty bytes of its
  unzeroed local record as if they were a live string handle. With the pass in
  place every row below matches the native build.

  WHAT MADE THIS REACHABLE. wasm32 had no arm in EmitZeroFrameSlot, so a local
  whose extent exceeds a pointer — a record with managed fields, a static array
  of string, a Variant — could not COMPILE for this target at all. The missing
  arm was also the guard. Giving the routine an explicit wasm32 no-op arm (its
  owner is the wasm prologue pass) removed the refusal and the protection in the
  same change, which is the shape that ships a use-after-free: hence this slice
  landing with the arm rather than after it.
  bug-a-emitzeroframeslot-has-no-wasm32-arm }
program ZeroInitSlice;

type
  TRow  = array of Integer;
  TR    = record S: string; N: Integer; end;
  TDeep = record Inner: TR; Tag: string; end;
  TStrs = array[0..3] of string;
  TRows = array[0..2] of TRow;

{ Leave a deep, non-zero frame behind so the next call's slots are dirty.
  Recursive so the dirt reaches well past one frame's worth. }
procedure Dirtier(d: Integer);
var a, b, c, e, f, g, h: NativeInt;
begin
  a := $11111111; b := $22222222; c := $33333333; e := $44444444;
  f := $55555555; g := $66666666; h := $77777777;
  if d > 0 then Dirtier(d - 1);
  if a + b + c + e + f + g + h = 0 then writeln('never');
end;

{ A local RECORD with a managed field, copied into. The copy releases the
  destination's old fields — so an unzeroed local releases stack garbage. }
function ViaRecord(const src: TR): TR;
var loc: TR;
begin
  loc := src;
  ViaRecord := loc;
end;

{ Two levels: the managed field is inside a nested record. }
function ViaDeep(const s: string): string;
var d: TDeep;
begin
  d.Inner.S := s;
  d.Inner.N := 1;
  d.Tag := 'tag';
  ViaDeep := d.Inner.S + '/' + d.Tag;
end;

{ A static ARRAY OF STRING local: every slot must start nil, not just the
  first — the extent is ArrLen * pointer, and an arm that zeroed one element's
  worth would leave [1..] dirty. }
function ViaStrArray: Integer;
var a: TStrs; i, n: Integer;
begin
  for i := 0 to 3 do a[i] := 'e' + Chr(48 + i);
  n := 0;
  for i := 0 to 3 do n := n + Length(a[i]);
  ViaStrArray := n;
end;

{ A static array of DYN-ARRAY HANDLES: SetLength on an element releases the
  old handle, so an unzeroed slot hands PXXDynArrayRelease stack garbage. }
function ViaRowArray: Integer;
var r: TRows; i, n: Integer;
begin
  for i := 0 to 2 do SetLength(r[i], i + 1);
  n := 0;
  for i := 0 to 2 do n := n + Length(r[i]);
  ViaRowArray := n;
end;

{ A plain managed scalar — the case that already worked, kept so a change that
  fixes the wide extents by breaking the narrow one is caught here. }
function ViaString(const s: string): string;
var loc: string;
begin
  loc := s;
  ViaString := loc;
end;

{ A local dynamic array — the other narrow case. }
function ViaDyn: Integer;
var d: TRow;
begin
  SetLength(d, 4);
  ViaDyn := Length(d);
end;

var src: TR;
begin
  src.S := 'payload';
  src.N := 5;

  Dirtier(6);
  writeln('record  ', ViaRecord(src).S, ' ', ViaRecord(src).N);
  Dirtier(6);
  writeln('deep    ', ViaDeep('inner'));
  Dirtier(6);
  writeln('strarr  ', ViaStrArray);
  Dirtier(6);
  writeln('rowarr  ', ViaRowArray);
  Dirtier(6);
  writeln('string  ', ViaString('scalar'));
  Dirtier(6);
  writeln('dyn     ', ViaDyn);
  writeln('done');
end.
