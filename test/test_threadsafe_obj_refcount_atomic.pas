program test_threadsafe_obj_refcount_atomic;
{ The OBJECT sibling of test_threadsafe_refcount_lockfree, which pins the same
  discipline for a managed STRING. PXXObjRetain/PXXObjRelease guarded their
  atomic arm on PXX_TS_SOFTLOCK -- the i386/aarch64/arm32 spelling of
  "--threadsafe" -- so on x86-64, which gets PXX_TS_HARDLOCK instead, both were a
  plain read-modify-write and OBJECT refcounts were racy in every threadsafe
  x86-64 build. The string half was already atomic (the codegen emits its own
  `lock inc qword [rax-16]` blob); this half is a Pascal helper that pylib
  CALLS, so no codegen blob reaches it.

  WHY THE ASSERTION IS A COUNT AND NOT A CRASH. A lost increment frees a live
  block and a lost decrement leaks one, and only the first has a visible
  symptom -- so a test that waits for a crash certifies half the defect as
  correct. Balanced retain/release pairs must bring the count back to EXACTLY
  where it started; anything else means the two directions stopped agreeing.
  Measured 2026-09-13 with the fix reverted, three runs: 400000 balanced pairs
  across the worker pool left the count off by 784, then 1306, then 972 -- a
  different amount every run, and always UP, which is a lost DECREMENT and so
  the invisible half. With the fix: fail=0 on every run.

  BIASED ON PURPOSE, and it is the row that makes this test report instead of
  dying: with a starting count of 1, a few hundred lost increments drive the
  refcount to zero, PXXObjRelease frees the block, and every later worker
  read-modify-writes freed memory -- a segfault, which is a failure but not a
  measurement. The bias is raised single-threaded first, so it cannot be reached
  by the race, and the final count is asserted against bias + 1 exactly.

  x86-64, --threadsafe. The default build defines neither lock symbol, so it is
  byte-identical and this program is a no-op assertion there (verified: the
  same hello compiled before and after the fix WITHOUT --threadsafe is
  byte-identical for both NilPy and Pascal).

  DELIBERATELY NOT A CONTAINER TEST. Two threads each building their OWN list
  segfault regardless of this fix, because NilPy object ALLOCATION takes no heap
  lock at all on x86-64 -- bug-a-a-nilpy-object-allocation-takes-no-heap-lock-on-
  x86-64-threadsafe, a separate and higher-priority defect. This test allocates
  exactly one block, single-threaded, before any worker starts, so it measures
  the refcount and nothing else. }
uses builtinheap, palparallel;

const
  N    = 400000;
  BIAS = 2000000;   { > N, so no run of lost increments can reach zero }

type
  PRefCnt = ^NativeInt;   { the refcount slot is a MACHINE WORD, as in the
                            string test -- a two-byte alias reads the low half
                            and happens to be right, which is how that test
                            once measured the wrong field }

var
  p: Pointer;
  k, fail: Integer;
  acc: Int64;
  before, after: Int64;

{ The refcount lives at base + PXX_HDR_RC, i.e. handle - PXX_HDR_SIZE +
  PXX_HDR_RC = handle - 16. Same slot the string test reads, same arithmetic. }
function RC(q: Pointer): Int64;
begin
  if q = nil then RC := -1
  else RC := PRefCnt(Int64(q) - 16)^;
end;

procedure Check(ok: Boolean; const what: AnsiString);
begin
  if not ok then
  begin
    WriteLn('FAIL ', what);
    fail := fail + 1;
  end;
end;

{ One balanced pair, in a frame of its own so nothing is captured by reference
  and shared between workers -- the enclosing-locals-are-shared trap the string
  test documents at length. }
function Touch: Integer;
begin
  PXXObjRetain(p);
  PXXObjRelease(p);
  Touch := 1;
end;

function Hammer(n: Integer): Int64;
var j: Integer; a: Int64;
begin
  a := 0;
  parallel(pdChunked) for j := 0 to n - 1 reduction(+: a) do
    a := a + Touch;
  Hammer := a;
end;

begin
  fail := 0;

  p := PXXObjAlloc(64);
  Check(p <> nil, 'PXXObjAlloc returned a block');
  Check(RC(p) = 1, 'a fresh object block starts at rc=1');

  { raise the bias single-threaded: this loop is not under test }
  for k := 1 to BIAS do PXXObjRetain(p);
  Check(RC(p) = BIAS + 1, 'the bias was applied exactly');

  before := RC(p);
  acc := Hammer(N);
  after := RC(p);

  Check(acc = N, 'every iteration ran');
  { THE ROW. Balanced pairs; the count must be bit-identical afterwards. }
  Check(after = before, 'the refcount came back to exactly where it started');
  if after <> before then
    WriteLn('  drift=', after - before, ' of ', N, ' pairs');

  { give the bias back and let the block go, so the test leaks nothing }
  for k := 1 to BIAS do PXXObjRelease(p);
  Check(RC(p) = 1, 'the bias was returned exactly');
  PXXObjRelease(p);

  WriteLn('fail=', fail);
  if fail = 0 then WriteLn('TSOBJRC OK') else WriteLn('TSOBJRC FAILED');
end.
