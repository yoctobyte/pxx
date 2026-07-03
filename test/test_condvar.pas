program test_condvar;
{ TConditionVariable (futex sequence-counter condvar): a bounded
  producer/consumer queue where consumers CondWait on "not empty" and the
  producer CondWait's on "not full", with CondSignal/CondBroadcast driving
  both directions. Every item must arrive exactly once (sum check), which a
  lost wakeup or a mutual-exclusion hole would break. Compile with
  --threadsafe. }
uses palthread, palsync;

const
  NCONS = 4;
  NITEMS = 20000;    { per consumer }
  QCAP = 8;

var
  lock:     TMutex;
  notEmpty: TCondVar;
  notFull:  TCondVar;
  q:        array[0..QCAP-1] of Integer;
  qHead, qTail, qCount: Integer;
  consumed: Int64;    { sum of consumed items, under lock }
  nTaken:   Integer;  { total items consumed, under lock }
  handles:  array[0..NCONS-1] of TThreadHandle;

procedure Consumer(arg: Pointer);
var
  i, v: Integer;
begin
  for i := 1 to NITEMS do
  begin
    MutexLock(lock);
    while qCount = 0 do
      CondWait(notEmpty, lock);
    v := q[qHead];
    qHead := (qHead + 1) mod QCAP;
    qCount := qCount - 1;
    consumed := consumed + v;
    nTaken := nTaken + 1;
    MutexUnlock(lock);
    CondSignal(notFull);
  end;
end;

var
  i, total: Integer;
  expected: Int64;
begin
  MutexInit(lock);
  CondInit(notEmpty);
  CondInit(notFull);
  qHead := 0; qTail := 0; qCount := 0;
  consumed := 0; nTaken := 0;

  for i := 0 to NCONS-1 do
    PalThreadCreate(handles[i], @Consumer, nil, 0);

  total := NCONS * NITEMS;
  expected := 0;
  for i := 1 to total do
  begin
    MutexLock(lock);
    while qCount = QCAP do
      CondWait(notFull, lock);
    q[qTail] := i;
    qTail := (qTail + 1) mod QCAP;
    qCount := qCount + 1;
    MutexUnlock(lock);
    { broadcast every 1024th item to exercise the wake-all path too }
    if (i mod 1024) = 0 then CondBroadcast(notEmpty)
    else CondSignal(notEmpty);
    expected := expected + i;
  end;

  for i := 0 to NCONS-1 do
    PalThreadJoin(handles[i]);

  writeln('taken=', nTaken, ' expected=', total);
  writeln('sum=', consumed, ' expected=', expected);
  if (nTaken = total) and (consumed = expected) then writeln('CONDVAR OK');
end.
