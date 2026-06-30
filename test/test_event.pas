program test_event;
{ M2: futex TEvent (x86-64). A manual-reset event as a start gun: NT worker threads
  each EventWait on it, then atomically bump a counter; the main thread fires
  EventSet once. Manual reset is level-triggered, so it is correct whether the
  workers park first (woken by EventSet) or arrive late (see it already signalled);
  either way every worker must pass. A failure to wake would hang the join. Builds
  on the M1/M2 PAL — libc-free. }
uses palthread, palsync;

const
  NT = 4;

var
  gun:    TEvent;
  passed: Integer;    { workers released past the gate (atomic) }

procedure Worker(arg: Pointer);
var ignore: Int64;
begin
  EventWait(gun);                       { block until main fires the gun }
  ignore := __pxxatomic_add(@passed, 1);
end;

var
  h: array[0..NT-1] of TThreadHandle;
  i: Integer;
begin
  EventInit(gun, True);                 { manual reset }
  passed := 0;

  for i := 0 to NT - 1 do
    if PalThreadCreate(h[i], @Worker, nil, 0) <> 0 then
    begin writeln('spawn FAIL ', i); Halt(1); end;

  EventSet(gun);                        { release everyone }

  for i := 0 to NT - 1 do
    PalThreadJoin(h[i]);

  writeln('passed=', passed, ' expected=', NT);
  if passed = NT then writeln('EVENT OK') else writeln('EVENT FAIL');
end.
