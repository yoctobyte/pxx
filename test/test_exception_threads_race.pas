program test_exception_threads_race;
{ Exceptions on two threads at once
  (bug-a-the-exception-shadow-chain-is-process-wide-so-two-threads-crash).

  BSS_EXC_TOP is the head of the setjmp shadow chain the unwinder walks: every
  `try` pushes a frame onto it, every exit pops it. While that head was one
  process-wide slot, thread A's `try` linked onto thread B's frame and a raise
  longjmped into a frame that might already be dead -- so this failed by
  CRASHING (SIGSEGV, or exit 217 with an exception that escaped its own `try`),
  not by answering wrong. Measured before the fix: 7 of 8 runs of phase 2 failed,
  with phase 1 of the same binary clean every time.

  Phase 1 is that single-threaded control and it runs FIRST, in the same
  process: a count from phase 2 means nothing without a run that cannot produce
  the failure. Phase 2 adds one thread and changes nothing else.

  ALLOCATION-FREE IN BOTH LOOPS, which is not an optimisation but the whole
  point: an exception that allocates takes the heap lock on every raise, which
  serialises the threads and hides the interleaving under test. Phase 3's
  objects are created once, before the thread starts, and only re-raised.

  Phase 3 exists because the chain head is not the only shared slot: the
  exception OBJECT and its CLASS INDEX were process-wide too, and those produce a
  wrong ANSWER rather than a crash. Each thread raises its own class in a loop
  and must catch its own; a class-index race lands in the `else` arm and is
  counted. That is a check the crash cannot make for us.

  THIS IS A RACE, NOT A DETERMINISTIC BREAK. N=100 and N=10000 have both passed
  on the broken build while N=1000 failed, so the counts here are large on
  purpose. One green run was never a fix. ~1s.

  x86-64 only, like every thread test in this repo -- and the fix is too: the
  TLS block exists only there, which is also the only target where pxx can
  create a thread at all (palthread compile-errors at the __pxxclone call site
  elsewhere). }

{$THREADSAFE ON}

const N = 100000;

type
  TAlphaError = class Code: Integer; end;
  TBetaError  = class Code: Integer; end;

var
  hitsA, hitsB, wrongA, wrongB, ready, go: Integer;
  objA: TAlphaError;
  objB: TBetaError;
  id: TThreadID;

{ The crash detector: no objects, no allocation, nothing but chain traffic. }
procedure SpinRaw(var hits: Integer; tag: Integer);
var i: Integer;
begin
  for i := 1 to N do
    try
      raise tag;
    except
      hits := hits + 1;
    end;
end;

{ The wrong-answer detector: each thread must catch the class IT raised. }
procedure SpinAlpha(var hits, wrong: Integer);
var i: Integer;
begin
  for i := 1 to N do
    try
      raise objA;
    except
      on E: TAlphaError do hits := hits + 1;
      else wrong := wrong + 1;
    end;
end;

procedure SpinBeta(var hits, wrong: Integer);
var i: Integer;
begin
  for i := 1 to N do
    try
      raise objB;
    except
      on E: TBetaError do hits := hits + 1;
      else wrong := wrong + 1;
    end;
end;

function Body(p: Pointer): PtrInt;
begin
  ready := 1;
  while go = 0 do ;
  SpinRaw(hitsB, 7);
  SpinBeta(hitsB, wrongB);
  Body := 0;
end;

begin
  objA := TAlphaError.Create; objA.Code := 1;
  objB := TBetaError.Create;  objB.Code := 2;

  { phase 1 — the control }
  SpinRaw(hitsA, 5);
  SpinAlpha(hitsA, wrongA);
  WriteLn('single hits=', hitsA, ' wrong=', wrongA);

  { phase 2+3 — one more thread, nothing else different }
  hitsA := 0; wrongA := 0;
  id := BeginThread(@Body, nil);
  while ready = 0 do ;
  go := 1;
  SpinRaw(hitsA, 5);
  SpinAlpha(hitsA, wrongA);
  WaitForThreadTerminate(id, 0);

  WriteLn('two hitsA=', hitsA, ' hitsB=', hitsB, ' wrongA=', wrongA, ' wrongB=', wrongB);
end.
