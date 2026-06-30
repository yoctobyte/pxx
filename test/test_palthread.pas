program test_palthread;
{ M1: exercise the libc-free thread PAL (lib/rtl/palthread.pas) — the same N-thread
  spawn/join smoke test as test_thread_clone, but through PalThreadCreate /
  PalThreadJoin / PalThreadSelf instead of raw syscalls. x86-64. }
uses palthread;

const
  NT = 4;

var
  results: array[0..NT-1] of Integer;
  selftid: array[0..NT-1] of Int64;

procedure ThreadEntry(arg: Pointer);
var
  k, spin: Int64;
begin
  k := Int64(arg);
  spin := 0;
  while spin < 2000000 do spin := spin + 1;   { encourage real overlap }
  selftid[k] := PalThreadSelf;
  results[k] := 1000 + k;
end;

var
  h: array[0..NT-1] of TThreadHandle;
  i, okCount: Integer;
  rc: Integer;
begin
  for i := 0 to NT - 1 do
  begin
    results[i] := 0;
    selftid[i] := 0;
    rc := PalThreadCreate(h[i], @ThreadEntry, Pointer(i), 0);
    if rc <> 0 then begin writeln('PalThreadCreate FAIL ', i); Halt(1); end;
  end;

  for i := 0 to NT - 1 do
    PalThreadJoin(h[i]);

  okCount := 0;
  for i := 0 to NT - 1 do
  begin
    { tids are nondeterministic, so keep them out of stdout (gate matches exact
      output) — the >0 check stays internal. }
    writeln('thread ', i, ' -> ', results[i]);
    if (results[i] = 1000 + i) and (selftid[i] > 0) then okCount := okCount + 1;
  end;

  writeln('total ok ', okCount, ' / ', NT);
  if okCount = NT then writeln('PALTHREAD OK') else writeln('PALTHREAD FAIL');
end.
