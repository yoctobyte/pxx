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

{ The refcount field at [handle-16] is a MACHINE WORD, so read it through a
  machine-word alias declared right here. It used to say `PWord`, which worked
  only because builtinheap's implementation-section `PWord = ^NativeInt` leaked
  into this program and shadowed the builtin `PWord = ^UInt16`. With that name
  fixed, `PWord` correctly means two bytes -- and the saturated literal sentinel
  $40000000 reads back as 0, so `born saturated` failed. The instrument was
  reading eight bytes through a name that means two.
  bug-p-a-units-implementation-section-is-visible-to-its-importers }
type PRefCnt = ^NativeInt;

function RC(const v: AnsiString): Int64;
begin
  if Pointer(v) = nil then RC := -1
  else RC := PRefCnt(Int64(Pointer(v)) - 16)^;
end;

{ The meta word at handle-24. MSTR_FLAG_STATIC ($0100) is the runtime's OWN
  answer to "is this block in the image", and it is a DIFFERENT FIELD from the
  refcount the rows below are about. That separation is the point: deciding the
  shape from the count and then asserting the count would be one field agreeing
  with itself. Value pinned to compiler/defs.inc, the way
  compiler/builtin/builtinheap.pas pins its copy.

  PRefCnt for the same reason the note above gives: meta is a machine word too.
  A two-byte read would still answer correctly here, since $0100 lives in the
  low half -- which is exactly why it is spelled the wide way rather than left
  to be right by luck. }
function IsStaticBlock(const v: AnsiString): Boolean;
begin
  if Pointer(v) = nil then IsStaticBlock := False
  else IsStaticBlock := (PRefCnt(Int64(Pointer(v)) - 24)^ and $0100) <> 0;
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

var acc: Int64; litRC0: Int64; litStatic: Boolean; nLit: Integer;
begin
  fail := 0;

  shared := '';
  for k := 1 to 44 do shared := shared + Chr(65 + (k mod 26));
  lit := 'a static literal handle';

  Check(RC(shared) = 1, 'heap handle starts at rc=1');
  litRC0 := RC(lit);
  { EITHER REPRESENTATION IS CORRECT AND THE LEVEL PICKS ONE. Since 440c822e6
    the static-literal handle (a ready-made saturated header in the image, no
    allocation and no copy) is emitted at -O2 AND ABOVE; below that the literal
    becomes an ordinary refcounted heap copy, and EmitStaticLitHandle's
    `if OptLevel < 2 then Exit` says so deliberately. The REPRESENTATION is
    built at every level; only its USE is gated.

    This row asserted saturation flatly, so the whole test printed
    TSRCLOCKFREE FAILED at -O0/-O1 and OK at -O2/-O3, rc=0 in all four -- a
    silent wrong answer that changed with the level, which is exactly the class
    tools/optdiff.sh exists to catch. It was invisible until 2026-09-01 because
    the program did not BUILD under that sweep (it needs --threadsafe) and the
    sweep's -O2 arm was comparing -O2 against -O2.

    What this test is FOR is that a literal handle is not corrupted by
    concurrent churn, and that survives the representation split. So the rows
    below assert the invariant both shapes must satisfy -- the count comes back
    to where it started -- and this one only records which shape is in play. }
  { ASK THE META WORD WHICH SHAPE IT IS, then assert the count that shape must
    have. A disjunction over the two counts -- `(litRC0 >= $40000000) or
    (litRC0 = 1)` -- records the split correctly and accepts one state that
    matters: a block whose meta says STATIC carrying a count of 1. That is a
    literal in the data section that PXXStrDecRef can walk to zero and free,
    which is the exact failure MSTR_STATIC_RC exists to prevent, and it
    satisfies the second arm. Branching on the independent field rejects it. }
  litStatic := IsStaticBlock(lit);
  if litStatic then
    Check(litRC0 >= $40000000, 'static literal block is born saturated')
  else
    Check(litRC0 = 1, 'heap-materialised literal is born with one counted ref');

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
  nLit := 0;
  for i := 0 to 63 do
    if (i mod 3) = 0 then arr[i] := ''
    else if (i mod 3) = 1 then begin arr[i] := lit; nLit := nLit + 1; end
    else arr[i] := shared;
  { Counted, not written as 21, so editing the loop cannot leave a stale
    constant in the assertion below quietly passing. }
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
  { MID-CHURN, while the array still holds its references, and only for the
    counted shape -- the post-drop row below is the one both shapes share.
    Worth having on top of it because the two fail differently: post-drop
    equality reconciles retains against releases in AGGREGATE, so a lost
    increment matched by a lost decrement returns to litRC0 and passes. This
    one names the number that must be there while the references are live. The
    saturated shape cannot ask the question at all -- its count is the same
    number whatever happens to it -- so at -O2 and above this file's coverage
    of the SetLength retain/release loops rests on the payload rows, and at
    -O0/-O1 it rests here. }
  if not litStatic then
    Check(RC(lit) = litRC0 + nLit,
          'counted literal holds exactly one ref per live array element');
  Check(Length(shared) = 44, 'shared payload survived SetLength churn');
  SetLength(arr, 0);
  Check(RC(shared) = 1, 'heap handle back to rc=1 after the array dropped it');
  { AFTER the array is dropped, not before. A saturated handle reads litRC0 at
    both points; a counted one legitimately reads litRC0 + (elements holding it)
    while the array is live, so comparing mid-churn asserted the -O2 shape
    rather than the property. Here both shapes must agree, and a churn that
    loses or double-counts a reference -- which is what a raced retain/release
    looks like -- fails it under either. }
  Check(RC(lit) = litRC0, 'literal count back where it started once the array dropped it');

  { The OK line is CONDITIONAL. An earlier draft printed it unconditionally and
    the positive control below caught that: a broken compiler produced `fail=2`
    followed by `TSRCLOCKFREE OK`, which is this repo's signature failure — a
    guard that reports PASS while failing. The `fail=` line alone would have
    been enough for expect_same, but not for a human reading `tail -1`.

    POSITIVE CONTROL, run rather than asserted: with the retain blob's
    `lock inc` weakened to a plain `inc` (still unlocked), this test reports
    fail=2 on every run of three — the parallel hammer and the array drop both
    detect the lost increments. With the atomic form, fail=0. So the guard can
    fail, and the `lock` prefix is load-bearing rather than defensive.

    THAT CONTROL HAS TO BE AIMED, and two of the three places it looks aimable
    are silent. `ir_codegen.inc` has THREE `lock inc qword [rax-16]` sites and
    only the retain BLOB's own (~3700, inside the nil/static-guarded blob) is
    what this program races. Weakening instead the two `incOp` sites in
    EmitAnsiStrRetain* (~428, ~473) — the callers that still hold the heap lock,
    so nothing here races them — leaves this test at fail=0 on every run of
    three at BOTH -O0 and -O2. A control pointed at the wrong one of three
    identical-looking sites reports exactly what a neutered test reports, so
    "I weakened the retain and nothing failed" is not evidence about the test.

    AND ITS ANSWER IS LEVEL-SCOPED, which is why the Makefile builds this
    program at -O0 as well as at the default. Blob weakened, three runs each,
    measured at 5df66928aa39, every run failing:

      -O2   2 FAILs   heap handle back to rc=1 after the parallel hammer
                      heap handle back to rc=1 after the array dropped it
      -O0   3 FAILs   literal count bit-identical — the block was never written
                      heap payload intact
                      shared payload survived SetLength churn

    At -O2 the literal is the static saturated handle, never retained and never
    released, so its rows CANNOT fail there however broken the retain is. At -O0
    it is an ordinary heap block and the sets swap over — and it fires as
    PAYLOAD CORRUPTION rather than as a wrong count, because a lost increment
    frees a live block. Neither level's failing set contains the other's, so one
    build of this program can only ever exercise half of what it asserts.

    THREE MORE for the representation branch, RE-RUN at 0f1d03315f4e after the
    PWord fix above landed (the earlier numbers were taken at 480d4584403c and
    the perturbations were spelled against the old `PWord` reads, so they would
    no longer have applied -- each sed below was checked to have actually
    changed the file before the binary was built, which is the half of a control
    that is easy to skip). The branch is the part that could quietly disable
    half the file, so every arm was made to fail on purpose:

      mid-churn count -> `litRC0 + nLit + 1`   : -O0 fail=1, -O2 fail=0
      IsStaticBlock forced False               : -O2 fail=2, -O0 fail=0
      IsStaticBlock forced True                : -O0 fail=1, -O2 fail=0

    The last two are the ones to keep in mind: THE PREDICATE IS SELF-GUARDING IN
    BOTH DIRECTIONS. A broken IsStaticBlock cannot route a level into the wrong
    arm and get away with it, because each arm asserts a count the other
    representation does not have — 1 against $40000000. That only holds because
    the branch is DECIDED by the meta word and CHECKED against the refcount
    word. Decide it from the count and the test agrees with itself at every
    level and fails at none. }
  WriteLn('fail=', fail);
  if fail = 0 then WriteLn('TSRCLOCKFREE OK')
  else WriteLn('TSRCLOCKFREE FAILED');
end.
