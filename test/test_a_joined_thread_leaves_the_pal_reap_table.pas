{ A JOINED THREAD MUST LEAVE THE PAL'S REAP TABLE.

  palthread registers every cloned thread's handle so a thread nobody joins
  still gets its stack back. PalThreadJoin released the stack and left the
  handle in the table until the next sweep. Every caller frees its handle right
  after the join (TThread.Destroy, CloseThread, crtl's pthread slots), so the
  table then held freed memory, and the sweep read TidWord and StackBase out of
  it. Found 2026-09-25 by the thread leak census.

  Built with -dPXX_HEAP_DEBUG so the outcome is deterministic: freed bytes
  become $DD, a stale entry's TidWord reads as a live thread, and it is never
  dropped. 300 join-and-free threads then fill the 256-slot table, and the
  stacks of the next 200 NEVER-joined threads are never reclaimed. Measured
  before the fix: +399 mappings, +205 MB of address space. After: +13. Without
  HEAP_DEBUG the stale words are whatever the heap reused them for, which is
  the dangerous version: a StackBase read from reused memory is an munmap of
  an arbitrary address. }
program test_a_joined_thread_leaves_the_pal_reap_table;
{$mode objfpc}
uses palthreadobj, sysutils;

type TW = class(TThread) procedure Execute; override; end;
procedure TW.Execute; begin ReturnValue := 1; end;

function Body(p: Pointer): PtrInt; begin Result := 0; end;

function MapCount: Integer;
var f: Text; line: string;
begin
  Result := 0;
  Assign(f, '/proc/self/maps'); Reset(f);
  while not Eof(f) do begin ReadLn(f, line); Inc(Result); end;
  Close(f);
end;

var i, before, after: Integer; t: TW; id: TThreadID;
begin
  for i := 1 to 300 do
  begin
    t := TW.Create(True); t.FreeOnTerminate := False; t.Start; t.WaitFor; t.Free;
  end;
  before := MapCount;
  for i := 1 to 200 do begin id := BeginThread(@Body, nil); Sleep(1); end;
  Sleep(50);
  after := MapCount;
  { A never-joined thread's stack is two mappings (the guard page splits it).
    Reclaimed, the growth is bounded by the threads still running at the last
    sweep; unreclaimed it is 2 per thread, about 400. }
  if after - before < 60 then
    writeln('REAPTABLE OK')
  else
    writeln('REAPTABLE FAIL: +', after - before, ' mappings over 200 never-joined threads');
end.
