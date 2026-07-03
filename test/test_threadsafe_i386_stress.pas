program test_threadsafe_i386_stress;
{ i386 --threadsafe softlock stress: concurrent GetMem/FreeMem + managed
  AnsiString churn from 4 threads. Any allocator corruption or refcount race
  crashes or corrupts the counts. }
uses palthread, palsync;
const NT = 4; ROUNDS = 20000;
var
  lock: TMutex;
  okCount: Integer;
  handles: array[0..NT-1] of TThreadHandle;
procedure Worker(arg: Pointer);
var
  i, j: Integer;
  p: Pointer;
  s, t: AnsiString;
begin
  for i := 1 to ROUNDS do
  begin
    GetMem(p, 16 + (i mod 64));
    s := 'abc';
    t := s + 'def';         { concat allocates }
    s := t;                 { retain/release churn }
    j := Length(s);
    FreeMem(p);
    if j = 6 then
    begin
      MutexLock(lock);
      okCount := okCount + 1;
      MutexUnlock(lock);
    end;
    s := ''; t := '';
  end;
end;
var i: Integer;
begin
  MutexInit(lock);
  okCount := 0;
  for i := 0 to NT-1 do PalThreadCreate(handles[i], @Worker, nil, 0);
  for i := 0 to NT-1 do PalThreadJoin(handles[i]);
  writeln('ok=', okCount, ' expected=', NT*ROUNDS);
  if okCount = NT*ROUNDS then writeln('HEAPSTRESS386 OK');
end.
