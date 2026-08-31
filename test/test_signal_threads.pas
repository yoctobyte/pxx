program test_signal_threads;
{ Signal delivery under --threadsafe: which thread runs the handler, and mask
  inheritance across clone(2). feature-signal-siginfo-ucontext item 2.

  The three properties this pins down, all MEASURED before being written here:

  1. The DISPOSITION is process-wide. `SetSignalHandler` from the main thread
     covers every thread, because it is one `rt_sigaction` on a process-wide
     table -- pxx does nothing per-thread and does not need to.
  2. The MASK is per-thread and INHERITED. A thread cloned from a main that
     blocks SIGUSR1 starts blocking it, and unblocking it in the worker does not
     unblock it in main.
  3. `__pxxSigNum` is correct from a NON-MAIN thread. It reads a process-wide
     BSS slot the dispatch stub writes, and the handler runs on whichever thread
     the kernel picked -- so this is the check that the slot is not somehow tied
     to the installing thread.

  THIS IS x86-64 ONLY, ON PURPOSE, and the reason is not the signal code:
  NO thread test in this repo runs cross-target -- test_thread_clone,
  test_palthread, test_mutex and test_tthread are all native-only -- so this
  joins that cluster rather than starting a new precedent. (It does not need
  -Fulib/rtl; BeginThread is reachable without it. It DOES need --threadsafe,
  like every test in that cluster.) Properties 1 and 2 are the KERNEL's and are
  identical on every Linux port, so per-arch copies would be testing Linux
  rather than pxx. Property 3 is ours, and the four cross suites cover the
  equivalent ground with test_signal_num and test_signal_bss_alias.

  EVERY ROW HERE HAS BEEN WATCHED FAILING, by three source-level controls:
  a worker that unblocks before the tkill (pending-while-blocked FALSE,
  hits-before-unblock 1), a tkill aimed at main instead (ran-on-worker FALSE,
  signum 0, total-hits 0), and a main that never blocks (inherited-block FALSE).
  The first of those is why the pending check is a `rt_sigpending` call rather
  than a counter: the original version had main read `hits` right after the
  tkill, which is a CROSS-THREAD read that raced -- it printed the passing value
  under the control too, and was measuring nothing.

  The pending-signal step is the load-bearing one. A thread-directed signal that
  is blocked stays pending ON THAT THREAD, so unblocking it in the worker is
  what delivers it -- and if the mask had NOT been inherited the handler would
  have run at tkill time instead, which `blocked-hits=0` catches. }

const
  SYS_gettid = 186; SYS_tkill = 200; SYS_rt_sigprocmask = 14;   { x86-64 }
  SYS_rt_sigpending = 127;
  SIG_BLOCK = 0; SIG_UNBLOCK = 1;
  USR1 = 10;

var
  mainTid, workerTid, hookTid, workerMask, pendingMask, r, blocked: Int64;
  hits, sawNum, ready, go, hitsBeforeUnblock: Integer;
  id: TThreadID;

function Tid: Int64; begin Tid := __pxxrawsyscall(SYS_gettid); end;

procedure Hook;
begin
  hookTid := Tid;
  sawNum := __pxxSigNum;
  hits := hits + 1;
end;

function Body(p: Pointer): PtrInt;
begin
  workerTid := Tid;
  { this thread's inherited blocked mask }
  r := __pxxrawsyscall(SYS_rt_sigprocmask, SIG_BLOCK, 0, PtrUInt(@workerMask), 8, 0, 0);
  ready := 1;
  while go = 0 do ;
  { Main tkill'd us before setting go, so the signal is queued by now. Ask the
    KERNEL whether it is pending rather than inferring it from a counter main
    reads on the other thread -- that read raced, and a control proved it: a
    worker that unblocked early still showed blocked-hits=0, because main read
    the count before this thread had run the handler. Both reads below are
    same-thread and ordered against our own handler. }
  r := __pxxrawsyscall(SYS_rt_sigpending, PtrUInt(@pendingMask), 8, 0, 0, 0, 0);
  hitsBeforeUnblock := hits;
  { pending and blocked; unblocking delivers it HERE, on this thread }
  r := __pxxrawsyscall(SYS_rt_sigprocmask, SIG_UNBLOCK, PtrUInt(@blocked), 0, 8, 0, 0);
  Body := 0;
end;

begin
  mainTid := Tid;
  blocked := Int64(1) shl (USR1 - 1);
  r := __pxxrawsyscall(SYS_rt_sigprocmask, SIG_BLOCK, PtrUInt(@blocked), 0, 8, 0, 0);
  SetSignalHandler(USR1, @Hook);          { installed from MAIN, before the clone }

  id := BeginThread(@Body, nil);
  while ready = 0 do ;

  WriteLn('inherited-block=', (workerMask and blocked) <> 0);
  r := __pxxrawsyscall(SYS_tkill, workerTid, USR1);
  go := 1;
  WaitForThreadTerminate(id, 0);

  WriteLn('pending-while-blocked=', (pendingMask and blocked) <> 0);
  WriteLn('hits-before-unblock=', hitsBeforeUnblock);
  WriteLn('ran-on-worker=', hookTid = workerTid);
  WriteLn('ran-on-main=', hookTid = mainTid);
  WriteLn('signum-from-worker=', sawNum);
  WriteLn('total-hits=', hits);   { 1: the worker's delivery only — main is still blocking its own }
end.
