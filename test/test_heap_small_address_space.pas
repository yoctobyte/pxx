program test_heap_small_address_space;
{ A small program must run where the heap cannot map its 256 MiB arena chunk.

  Linux's default overcommit heuristic refuses ONE mapping larger than RAM +
  swap. On a 256 MB OpenWrt router (no swap) the first HEAP_ARENA chunk was
  refused and every program that allocated died at once with "pxx: out of
  memory (heap arena mmap failed)", exit 203, with nearly all memory free
  (measured 2026-11-12, OpenWrt 25.12.6 x86-64 in QEMU, 236 MB RAM). The heap
  now retries a refused map at half the size, down to 64 KiB.

  The Makefile runs this under `ulimit -v 200000`, below HEAP_ARENA, which
  refuses the 256 MiB map the same way on any host. Positive control: the
  compiler before the fix exits 203 here. The workload is a few MB, so it fits
  comfortably in the cap once the arena is sized to what the box allows. }
var
  s: AnsiString;
  a: array of AnsiString;
  i, total: Integer;
begin
  SetLength(a, 2000);
  total := 0;
  for i := 0 to High(a) do
  begin
    s := 'item-';
    s := s + StringOfChar('x', 1000 + (i mod 37));
    a[i] := s;
    total := total + Length(a[i]);
  end;
  writeln('small heap ok ', total);
end.
