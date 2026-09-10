{ SPDX-License-Identifier: Zlib }
unit pythreadlive;
{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
{ How many spawned threads are currently alive — one integer, and it exists so
  that `mimic_queue` can tell a WAIT from a DEADLOCK.

  ## Why this is a unit of its own and not a field in either caller

  `mimic_threading` is the writer and `mimic_queue` is the reader, and neither
  may depend on the other:

  * queue -> threading would pull `palthread` into every program that writes
    `import queue`, and palthread's `__pxxclone` refuses to compile without
    `--threadsafe`. A single-threaded program importing `queue` would stop
    building. That is the whole reason this is not simply a variable in
    mimic_threading.
  * threading -> queue would make `import threading` drag the Queue class in
    for no reason.

  So the shared fact lives below both, in a unit that depends on nothing. It is
  deliberately not in `palthread` (which is gated) and not in `palsync` (which
  is a general RTL primitive and owes nothing to Python's semantics).

  ## What it is NOT

  Not a thread registry, not a scheduler hook, and not accurate to the
  instant — a thread that has finished its body but not yet been joined still
  counts. That is exactly the precision the one consumer needs: it asks "could
  ANYTHING other than me satisfy this wait", and the answer only has to be
  conservative in the safe direction. Over-counting makes a queue WAIT where it
  could have diagnosed; under-counting would make it raise where a real
  hand-off was coming, which is the error that matters. }

interface

{ Called by mimic_threading around a spawned thread's lifetime. }
procedure PyThreadLiveInc;
procedure PyThreadLiveDec;
{ True when at least one spawned thread is alive, i.e. when a blocking wait has
  someone who could satisfy it. }
function PyThreadLiveAny: Boolean;

implementation

var
  gLive: Integer;

procedure PyThreadLiveInc;
begin
  { A plain increment, not an atomic one. The only WRITER is the thread that
    calls Thread.start, and starts are serialised by the program that writes
    them -- a Python program spawning threads from two threads at once is
    outside every shape this was measured against, and the reader tolerates a
    stale value by construction (see the unit header). Making this atomic would
    be free; saying it is atomic when it is not would not. }
  gLive := gLive + 1;
end;

procedure PyThreadLiveDec;
begin
  if gLive > 0 then gLive := gLive - 1;
end;

function PyThreadLiveAny: Boolean;
begin
  PyThreadLiveAny := gLive > 0;
end;

end.
