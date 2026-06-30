program test_mutex;
{ M2: futex mutex provides real mutual exclusion (x86-64). NT threads each do K
  NON-atomic increments (counter := counter + 1) of a shared counter, but inside
  MutexLock/MutexUnlock. With the lock the final value is exactly NT*K; without it
  the read-modify-write would race and lose updates. Builds on M1 (palthread). }
uses palthread, palsync;

const
  NT = 4;
  K  = 100000;

var
  counter: Integer;     { deliberately a plain int, mutated non-atomically }
  m: TMutex;

procedure Worker(arg: Pointer);
var
  j: Integer;
begin
  for j := 1 to K do
  begin
    MutexLock(m);
    counter := counter + 1;     { non-atomic — only safe under the mutex }
    MutexUnlock(m);
  end;
end;

var
  h: array[0..NT-1] of TThreadHandle;
  i, v: Integer;
begin
  MutexInit(m);
  counter := 0;

  for i := 0 to NT - 1 do
    if PalThreadCreate(h[i], @Worker, nil, 0) <> 0 then
    begin writeln('spawn FAIL ', i); Halt(1); end;
  for i := 0 to NT - 1 do
    PalThreadJoin(h[i]);

  v := counter;
  writeln('counter=', v, ' expected=', NT * K);
  if v = NT * K then writeln('MUTEX OK') else writeln('MUTEX FAIL');
end.
