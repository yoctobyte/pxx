program test_threadsafe_refcount_lockfree;
{ The --threadsafe refcount discipline: retains and releases are ATOMIC and take
  NO heap lock. Guards bug-a-a-shared-ansistring-handle-in-a-parallel-loop-is-
  11x-slower, whose second half was that a shared HEAP handle still queued twelve
  workers on the global spinlock to perform an operation the CPU already makes
  atomic.

  What could break if the change regressed, and each has an assertion below:

    - a LOST INCREMENT. The retain blob now does `lock inc` without the lock,
      while EmitAnsiStrRetainLocked's two SetLength callers still run with it
      held; if either went back to a plain `inc` the two populations would race
      and an increment would vanish. A vanished increment FREES A LIVE BLOCK, so
      the symptom is a wrong payload or a crash, not a wrong count.
    - an OVER-RELEASE. The decrement is unlocked and the heap lock is taken only
      on the zero path, so a refcount that does not return to exactly 1 after N
      balanced copies means the two directions no longer agree.
    - a WRITTEN STATIC BLOCK. The saturation guard sits above all of this; a
      literal handle's count must be bit-identical afterwards, because the
      block lives in the data section beside code.

  Deliberately RACE-FREE, and that is load-bearing rather than tidy: enclosing
  locals are captured BY REFERENCE and so are SHARED between workers
  (docs/library/concurrency.md), so a temp declared in the enclosing function
  and written from the body is a data race, and a racy test reports a corrupt
  refcount whatever the compiler does. Both this compiler and its predecessor
  "fail" such a test identically. The temp therefore lives in Touch's own frame,
  which is per-call and so per-worker.

  x86-64, --threadsafe. }
uses builtinheap, palparallel;

const
  N = 400000;

var
  shared, lit: AnsiString;
  arr: array of AnsiString;
  k, i, fail: Integer;

function RC(const v: AnsiString): Int64;
begin
  if Pointer(v) = nil then RC := -1
  else RC := PWord(Int64(Pointer(v)) - 16)^;
end;

procedure Check(ok: Boolean; const what: AnsiString);
begin
  if not ok then
  begin
    WriteLn('FAIL ', what);
    fail := fail + 1;
  end;
end;

{ One balanced retain+release of `src`, in a frame of its own. }
function Touch(const src: AnsiString): Integer;
var s: AnsiString;
begin
  s := src;
  Touch := Length(s);
end;

function Hammer(n: Integer): Int64;
var j: Integer; acc: Int64;
begin
  acc := 0;
  parallel(pdChunked) for j := 0 to n - 1 reduction(+: acc) do
    acc := acc + Touch(shared) + Touch(lit);
  Hammer := acc;
end;

var acc: Int64; litRC0: Int64;
begin
  fail := 0;

  shared := '';
  for k := 1 to 44 do shared := shared + Chr(65 + (k mod 26));
  lit := 'a static literal handle';

  Check(RC(shared) = 1, 'heap handle starts at rc=1');
  litRC0 := RC(lit);
  Check(litRC0 >= $40000000, 'literal handle is born saturated');

  acc := Hammer(N);
  Check(acc = Int64(N) * (44 + 23), 'every parallel copy saw an intact payload');
  Check(RC(shared) = 1, 'heap handle back to rc=1 after the parallel hammer');
  Check(RC(lit) = litRC0, 'literal count bit-identical — the block was never written');
  Check(Length(shared) = 44, 'heap payload intact');

  { The SetLength element-retain/release loops — the two callers that still hold
    the heap lock while touching a refcount. Mixed nil and literal elements is
    the shape that caught a nil-deref when these tests were once stripped in
    favour of the blob's copy. }
  SetLength(arr, 64);
  for i := 0 to 63 do
    if (i mod 3) = 0 then arr[i] := ''
    else if (i mod 3) = 1 then arr[i] := lit
    else arr[i] := shared;
  for k := 1 to 200 do
  begin
    SetLength(arr, 512);
    SetLength(arr, 16);
    SetLength(arr, 64);
    for i := 0 to 63 do
      if (i mod 3) = 0 then arr[i] := ''
      else if (i mod 3) = 1 then arr[i] := lit
      else arr[i] := shared;
  end;
  Check(RC(lit) = litRC0, 'literal count still bit-identical after SetLength churn');
  Check(Length(shared) = 44, 'shared payload survived SetLength churn');
  SetLength(arr, 0);
  Check(RC(shared) = 1, 'heap handle back to rc=1 after the array dropped it');

  { The OK line is CONDITIONAL. An earlier draft printed it unconditionally and
    the positive control below caught that: a broken compiler produced `fail=2`
    followed by `TSRCLOCKFREE OK`, which is this repo's signature failure — a
    guard that reports PASS while failing. The `fail=` line alone would have
    been enough for expect_same, but not for a human reading `tail -1`.

    POSITIVE CONTROL, run rather than asserted: with the retain blob's
    `lock inc` weakened to a plain `inc` (still unlocked), this test reports
    fail=2 on every run of three — the parallel hammer and the array drop both
    detect the lost increments. With the atomic form, fail=0. So the guard can
    fail, and the `lock` prefix is load-bearing rather than defensive. }
  WriteLn('fail=', fail);
  if fail = 0 then WriteLn('TSRCLOCKFREE OK')
  else WriteLn('TSRCLOCKFREE FAILED');
end.
