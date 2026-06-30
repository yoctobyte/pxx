program test_critsec_once;
{ M2: FPC-compatible TRTLCriticalSection + RunOnce (x86-64). NT threads each:
  (1) RunOnce(@OnceInit) — across all racers the initialiser must run EXACTLY once;
  (2) K increments of a shared counter guarded by EnterCriticalSection/Leave.
  Final counter = NT*K (mutual exclusion) and init-ran = 1 (once semantics). Builds
  on the M1/M2/M3 PAL — libc-free. }
uses palthread, palsync, palthreadobj;

const
  NT = 8;
  K  = 50000;

var
  cs:        TRTLCriticalSection;
  csCounter: Integer;        { guarded by cs, mutated non-atomically }
  onceCtl:   TOnceControl;
  initRan:   Integer;        { times OnceInit executed (atomic) }

procedure OnceInit;
var ignore: Int64;
begin
  ignore := __pxxatomic_add(@initRan, 1);
end;

type
  TW = class(TThread)
  protected
    procedure Execute; override;
  end;

procedure TW.Execute;
var k: Integer;
begin
  RunOnce(onceCtl, @OnceInit);
  for k := 1 to K do
  begin
    EnterCriticalSection(cs);
    csCounter := csCounter + 1;
    LeaveCriticalSection(cs);
  end;
end;

var
  w: array[0..NT-1] of TW;
  i: Integer;
begin
  InitCriticalSection(cs);
  csCounter := 0;
  onceCtl := 0;
  initRan := 0;

  for i := 0 to NT - 1 do w[i] := TW.Create(True);
  for i := 0 to NT - 1 do w[i].Start;
  for i := 0 to NT - 1 do w[i].WaitFor;

  writeln('critsec=', csCounter, ' expected=', NT * K);
  writeln('init ran=', initRan, ' expected=1');
  if (csCounter = NT * K) and (initRan = 1) then writeln('CRITSEC_ONCE OK')
  else writeln('CRITSEC_ONCE FAIL');
end.
