{ FPC's LOW-LEVEL thread API is declared in the System unit, so portable
  threaded source calls BeginThread / EndThread / WaitForThreadTerminate /
  CloseThread and declares a `TThreadID` with NO uses line at all. (FPC's
  `cthreads` picks the thread MANAGER; it is not where these names live, so it
  is not the counterpart of pxx's palthreadobj.)

  pxx keeps them in palthreadobj — a real unit with a slot registry, a mutex and
  TThread itself — and pulls it on demand from a token scan, the way `math` is
  pulled for sqrt/ln. This file is the no-uses spelling, which is the one that
  was refused: `unknown type: TThreadID`, then `undefined variable
  (BeginThread)`.

  Rows:

    a  the body runs and its side effect is visible after the join
    b  WaitForThreadTerminate hands back the body's RESULT, and it survives the
       thread (that is what the slot registry is for)
    c  CloseThread releases the slot; calling it is not an error
    d  a second thread, so the pull is not a one-shot

  The uses line below names only SysUtils, exactly as the FPC original does.
  bug-p-the-fpc-low-level-thread-api-needs-a-uses-clause }
program test_thread_api_no_uses;
{$threadsafe on}

uses SysUtils;

var
  Done, Done2: Integer;

function Body(p: Pointer): PtrInt;
begin
  Done := PtrInt(p) * 3;
  Result := PtrInt(p) + 1;
end;

function Body2(p: Pointer): PtrInt;
begin
  Done2 := PtrInt(p) - 1;
  Result := 0;
end;

var
  h, h2: TThreadID;
  r: PtrInt;

begin
  Done := -1;
  Done2 := -1;

  h := BeginThread(@Body, Pointer(PtrInt(14)));
  r := WaitForThreadTerminate(h, 0);
  WriteLn('a ', Done);
  WriteLn('b ', r);
  CloseThread(h);
  WriteLn('c ok');

  h2 := BeginThread(@Body2, Pointer(PtrInt(9)));
  WaitForThreadTerminate(h2, 0);
  CloseThread(h2);
  WriteLn('d ', Done2);
end.
