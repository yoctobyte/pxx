{ The wasm32 heap past its first megabyte.

  HeapMmap's wasm arm used to hand out one fixed 1 MiB BSS arena and return -1
  for every request after it -- a hard ceiling that no other target has. It now
  calls memory.grow, reached from Pascal through `external 'wasm' name
  'memory.grow'`, which the backend lowers to the instruction inline rather
  than to an import.

  What that can get wrong: memory.grow returns the PREVIOUS SIZE IN PAGES, not
  the new size and not an address, so a base computed from the wrong one lands
  inside memory that is already in use -- and the corruption shows up somewhere
  else entirely. Hence the interleaving below: every block is written, then all
  of them are re-read after later growth, so a base that overlaps an earlier
  block is caught as a wrong byte rather than as a plausible total. }
program heapgrow_slice;
const N = 24;                     { 24 * 256 KB = 6 MB, well past the arena }
      BLK = 262144;
type PB = ^Byte;
var blocks: array[0..N - 1] of Pointer;
    i, k, bad: Integer; p: PB;
begin
  for i := 0 to N - 1 do
  begin
    blocks[i] := GetMem(BLK);
    if blocks[i] = nil then
    begin
      WriteLn('alloc_failed_at=', i);
      Halt(1);
    end;
    { touch the whole block: a base that overlaps declared-but-ungrown memory
      faults here rather than silently }
    for k := 0 to 15 do
    begin
      p := PB(Int64(blocks[i]) + k * (BLK div 16));
      p^ := Byte((i * 7 + k) and $FF);
    end;
  end;
  WriteLn('allocated=', N, ' blocks of ', BLK);

  bad := 0;
  for i := 0 to N - 1 do
    for k := 0 to 15 do
    begin
      p := PB(Int64(blocks[i]) + k * (BLK div 16));
      if p^ <> Byte((i * 7 + k) and $FF) then bad := bad + 1;
    end;
  WriteLn('corrupted=', bad);

  { fresh memory must be ZERO -- PXXAlloc's contract, which on this target is
    inherited from wasm's guarantee about new pages rather than from a memset }
  bad := 0;
  for i := 0 to N - 1 do
  begin
    p := PB(Int64(GetMem(BLK)) + 12345);
    if p^ <> 0 then bad := bad + 1;
  end;
  WriteLn('nonzero_fresh=', bad);

  for i := 0 to N - 1 do FreeMem(blocks[i]);
  WriteLn('done');
end.
