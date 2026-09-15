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
  gLive: LongInt;   { LongInt, not Integer: InterLocked* take a var LongInt. }

{ ATOMIC SINCE 2026-09-15, AND THE COMMENT THAT USED TO SIT HERE WAS WRONG
  ABOUT ITS OWN CODE. It said "the only WRITER is the thread that calls
  Thread.start, and starts are serialised by the program that writes them".
  There are three writers and only one of them is the parent:
  mimic_threading.pas calls Inc in Thread.start (parent) and Dec twice inside
  ThreadLauncher (the CHILD, at its normal end and on the non-callable early
  exit). So a dying child and a starting parent write one plain Integer with no
  ordering at all, and on a true count of 1 the interleaving

      parent reads 1 / child reads 1 / parent writes 2 / child writes 0

  leaves a live thread with the counter saying nothing is alive. The clamp on
  Dec catches a lost DECREMENT and nothing catches a lost increment, so the
  surviving error is the one the unit header calls "the error that matters":
  under-counting, which makes mimic_queue raise where a real hand-off was
  coming.

  Found by lekkerzeilen-c8 by READING, chasing an intermittent
  `queue.Queue.get() would block forever: no other thread is alive` that fires
  during world load at roughly one start in four while the main thread is
  demonstrably alive and busy. The unit header had already named this exact
  consequence, in this file, two paragraphs above the code that causes it.

  InterLockedIncrement/Decrement rather than a mutex: it is `lock xadd` on
  x86-64, it is what the old comment itself said would be free, and it needs no
  lock object in a unit that deliberately depends on nothing. Guarded for the
  two targets `builtin.pas` does not define them on; there the plain arm is
  what was always running. }
procedure PyThreadLiveInc;
begin
{$ifdef CPURISCV32}
  gLive := gLive + 1;
{$else}
{$ifdef CPUXTENSA}
  gLive := gLive + 1;
{$else}
  InterLockedIncrement(gLive);
{$endif}
{$endif}
end;

procedure PyThreadLiveDec;
begin
  { UNCONDITIONAL on the atomic arm, and the dropped `if gLive > 0` is not an
    oversight. Every Dec is now paired with an Inc that has ALREADY happened --
    mimic_threading increments before PalThreadCreate rather than after it, so
    no child can decrement a count its own start has not yet raised -- which
    means the count cannot go negative and the clamp guards nothing. Keeping it
    would be worse than useless: a compare-then-subtract is two operations and
    reintroduces exactly the race this procedure was made atomic to remove. }
{$ifdef CPURISCV32}
  if gLive > 0 then gLive := gLive - 1;
{$else}
{$ifdef CPUXTENSA}
  if gLive > 0 then gLive := gLive - 1;
{$else}
  InterLockedDecrement(gLive);
{$endif}
{$endif}
end;

function PyThreadLiveAny: Boolean;
begin
  PyThreadLiveAny := gLive > 0;
end;

end.
