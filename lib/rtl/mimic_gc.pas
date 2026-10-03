{ SPDX-License-Identifier: Zlib }
unit mimic_gc;
{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
{ MicroPython's (and CPython's) `gc`, which nearly every MicroPython script
  calls: `import gc; gc.collect(); print(gc.mem_free())`. Resolves through the
  NilPy import resolver's `mimic_` fallback, like mimic_time.

  BY DEFAULT THERE IS NO COLLECTOR. PXX frees by reference counting, so
  acyclic garbage is already gone by the time collect() would look for it,
  and collect() has nothing to do: it returns 0. A REFERENCE CYCLE IS NOT
  COLLECTED, and that is the one thing a MicroPython program can see differ:
  a cycle it drops stays allocated. Break the cycle (set a back-reference to
  None) before dropping it -- or build with -dPXX_CYCLE_GC, which links every
  object into a tracked list and collects cycles by trial deletion
  (builtinheap, PXXGcCollect): collect() then frees them and answers how many,
  automatic runs happen from the allocators, and enable()/disable()/
  isenabled() switch those runs. Not in a threadsafe build, where collect()
  stays 0.

  mem_free() and mem_alloc() are real figures. On the host they are this
  runtime's own heap, GetFPCHeapStatus: mem_alloc the live payload bytes,
  mem_free what the mapped arenas hold beyond that (0 on an allocator profile
  that reports no reserve; see GetFPCHeapStatus). On ESP32 under IDF (PXX_ESP_IDF) they are
  IDF's byte-addressable heap, MALLOC_CAP_8BIT, the one PXX allocates from:
  mem_free heap_caps_get_free_size, mem_alloc the total minus that.
  MicroPython's figures are its own GC arena and differ in size; what a script
  does with them -- watch mem_free stay level -- holds. ONE unit with an
  ifdef, not a second file in lib/rtl/platform/esp: ESP builds pass -Fulib/rtl
  before the platform dir, so a same-named unit there would lose.

  Without -dPXX_CYCLE_GC, enable(), disable(), isenabled() and threshold()
  are accepted and change nothing; threshold() answers -1, MicroPython's
  "not set" (and does with the collector too). }

interface

function collect: Integer;
function mem_free: Integer;
function mem_alloc: Integer;
procedure enable;
procedure disable;
function isenabled: Boolean;
function threshold: Integer; overload;
procedure threshold(amount: Integer); overload;

implementation

{$ifdef PXX_ESP_IDF}
const
  MALLOC_CAP_8BIT = 4;   { esp_heap_caps.h: byte-addressable memory }

function heap_caps_get_free_size(caps: LongWord): PtrUInt; external;
function heap_caps_get_total_size(caps: LongWord): PtrUInt; external;

function mem_free: Integer;
begin
  mem_free := Integer(heap_caps_get_free_size(MALLOC_CAP_8BIT));
end;

function mem_alloc: Integer;
begin
  mem_alloc := Integer(heap_caps_get_total_size(MALLOC_CAP_8BIT)) -
               Integer(heap_caps_get_free_size(MALLOC_CAP_8BIT));
end;
{$else}
function mem_free: Integer;
var h: TFPCHeapStatus;
begin
  h := GetFPCHeapStatus;
  mem_free := Integer(h.CurrHeapFree);
end;

function mem_alloc: Integer;
var h: TFPCHeapStatus;
begin
  h := GetFPCHeapStatus;
  mem_alloc := Integer(h.CurrHeapUsed);
end;
{$endif}

function collect: Integer;
begin
{$ifdef PXX_CYCLE_GC}
  { -dPXX_CYCLE_GC: the trial-deletion collector in builtinheap. Answers the
    number of objects freed, as CPython's does. 0 in a threadsafe build, where
    it does not run (see PXXGcCollect). }
  collect := Integer(PXXGcCollect);
{$else}
  collect := 0;
{$endif}
end;

procedure enable;
begin
{$ifdef PXX_CYCLE_GC}
  PXXGcEnable(True);
{$endif}
end;

procedure disable;
begin
{$ifdef PXX_CYCLE_GC}
  PXXGcEnable(False);
{$endif}
end;

function isenabled: Boolean;
begin
{$ifdef PXX_CYCLE_GC}
  isenabled := PXXGcEnabled;
{$else}
  isenabled := True;
{$endif}
end;

function threshold: Integer;
begin
  threshold := -1;
end;

procedure threshold(amount: Integer);
begin
end;

end.
