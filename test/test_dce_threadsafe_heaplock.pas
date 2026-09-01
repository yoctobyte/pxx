{ DCE must not break the --threadsafe heap lock.

  The whole program is one object allocated and freed. There are NO THREADS
  here on purpose: the bug this guards reproduced with a single task, and
  writing it as a threading test is what hid it for a day.

  WHAT BROKE (2026-09-01, five optdiff shards). DCE compacts the GlobFix table
  when it drops a body, and GlobFixPCRel / GlobFixTrail / GlobFixPicDelta are
  parallel to it BY INDEX -- deliberately outside TGlobFix, because that is a
  bootstrap record whose size the compiler asserts about itself. The compaction
  copied the record and not the parallel arrays, so every site that moved wore
  the flags of whoever previously sat at its new index.

  EmitReleaseHeapLock emits `mov dword [@glob], 0` -- C7 /0 with an imm32
  TRAILING the disp32 -- so its Trail is 4 and the rip correction must be
  -(4+4). Inheriting a Trail of 0 makes it -4 and the release stores four bytes
  PAST the lock word. The acquire (`lock xchg`, no immediate) was patched
  correctly, so the binary acquired a lock nothing ever cleared and spun
  forever with one thread alive. No crash and no diagnostic.

  WHY THIS ROW EXISTS AT ALL: before it, `--dce` appeared NOWHERE in this
  Makefile. The pass was reachable only through -O3, which the quick tier does
  not run, so the whole of DCE was covered by Track T's opt tier and by nothing
  a dev lane runs. A pass with no row of its own is a pass that ships broken.

  THE ASSERTION IS THE EXIT CODE AS WELL AS THE OUTPUT, and it runs under
  `timeout`: the failure mode is a HANG, and a row that compares only stdout
  cannot tell a hang from a slow box -- it just wedges. }
program test_dce_threadsafe_heaplock;

type
  TThing = class
  public
    v: Integer;
  end;

var
  t: TThing;
  i, n: Integer;

begin
  n := 0;
  { A loop, so the free path runs more than once: the lock is taken and
    released per allocation, and one round trip could pass on a stale lock. }
  for i := 1 to 64 do
  begin
    t := TThing.Create;
    t.v := i;
    n := n + t.v;
    t.Free;
  end;
  writeln('DCETSLOCK OK ', n);
end.
