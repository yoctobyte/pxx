{ SPDX-License-Identifier: Zlib }
unit espsys;
{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
{ ESP32 system facts a long-running program should watch: the heap, and time
  since boot. For Pascal and for Nil Python.

  WHY THE HEAP IS HERE. A device that is meant to keep running dies of a leak,
  and nothing else announces one: every value the program prints stays
  correct while the free heap walks down. So a program on the chip should be
  able to watch its own free heap, and the demos do, so that a soak is a
  number rather than a feeling. The acceptance for "no leak" is a FLAT
  free_heap after warm-up, next to a control loop that allocates nothing.

  free_heap is IDF's esp_get_free_heap_size: every byte-addressable region the
  allocator serves, internal SRAM plus PSRAM if the board has it. min_free_heap
  is the low-water mark since boot, which catches a transient peak that a
  periodic sample misses. largest_free_block is the biggest single allocation
  that would succeed now, and it is the number that falls first when the heap
  fragments.

  IDF-only: these resolve at IDF link time (esp_system, heap, esp_timer), all
  of which a default IDF project already requires. }

interface

{ Pascal surface. }
function EspFreeHeap: LongInt;
function EspMinFreeHeap: LongInt;
function EspLargestFreeBlock: LongInt;
function EspUptimeMs: Int64;

{ ---- the Nil Python surface ----------------------------------------------
      import 'espsys.pas' as sys
      print("free", sys.free_heap())                                        }
function free_heap: Integer;
function min_free_heap: Integer;
function largest_free_block: Integer;
function uptime_ms: Integer;

implementation

const
  MALLOC_CAP_8BIT = 4;   { esp_heap_caps.h: byte-addressable memory }

function esp_get_free_heap_size: LongWord; external;
function esp_get_minimum_free_heap_size: LongWord; external;
function heap_caps_get_largest_free_block(caps: LongWord): PtrUInt; external;
function esp_timer_get_time: Int64; external;

function EspFreeHeap: LongInt;
begin
  EspFreeHeap := LongInt(esp_get_free_heap_size);
end;

function EspMinFreeHeap: LongInt;
begin
  EspMinFreeHeap := LongInt(esp_get_minimum_free_heap_size);
end;

function EspLargestFreeBlock: LongInt;
begin
  EspLargestFreeBlock := LongInt(heap_caps_get_largest_free_block(MALLOC_CAP_8BIT));
end;

function EspUptimeMs: Int64;
begin
  EspUptimeMs := esp_timer_get_time div 1000;
end;

function free_heap: Integer;
begin
  free_heap := EspFreeHeap;
end;

function min_free_heap: Integer;
begin
  min_free_heap := EspMinFreeHeap;
end;

function largest_free_block: Integer;
begin
  largest_free_block := EspLargestFreeBlock;
end;

function uptime_ms: Integer;
begin
  uptime_ms := Integer(EspUptimeMs);
end;

end.
