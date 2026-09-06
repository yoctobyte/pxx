program test_parallel_for_private;
{ `private(v, ...)` on a `parallel for`: each worker gets its own copy of v,
  seeded to zero/empty and never combined back.

  WHAT IT IS FOR. A captured local is captured BY REFERENCE -- concurrency.md
  says so, and says an unguarded shared write is a data race -- so a body that
  needs SCRATCH storage had no race-free spelling. `reduction` was the only
  clause, and it gives a private PLUS a combine, which is the wrong shape for a
  temporary. Measured before this clause existed, with the SCRATCH loop below
  and the clause removed: five runs of a loop that must total 300000 gave
  298051, 298141, 299650, 299462, 299233. Exit 0 every time. Every worker was
  incrementing one shared `j` through one pointer.

  `private` is `reduction` minus the fold, and it reuses that machinery: the
  private local is declared in the worker's own var section and the name is
  excluded from the capture list, which is what an inner `for` control variable
  has done since bug-a-a-nested-for-loop-in-a-parallel-for-body-is-a-compile-error.
  feature-a-a-private-clause-for-parallel-for

  THE SEED ROW IS THE ONE THAT NEEDS DEFENDING, because OpenMP's `private` is
  deliberately UNINITIALISED and this one is not. Two reasons, and the second
  is why the row exists: managed types have no sensible uninitialised state;
  and an uninitialised local reads its stack slot, which in a freshly-entered
  worker frame is USUALLY ZERO -- so the unseeded behaviour is accidentally
  correct most of the time and wrong under load. Measured, with the seed
  emission disabled in the compiler and everything else identical: SEED printed
  11, not 0 -- the Integer and the Double came back dirty while the Boolean and
  the Char happened to land on zero bytes and passed. TWO OF FOUR COMPONENTS
  FIRED. Keep all four: which ones catch it is a property of the frame layout,
  not of the defect.

  Per WORKER, not per iteration. The seed row therefore pins `n 1` and a
  single iteration, so "the value at the first read" is a defined quantity.

  Build --threadsafe. }
uses palparallel;

const
  N = 100000;
  M = 20000;
  NSTR = 4000;

var gbad: Integer;

procedure Run;
var acc, bad, sacc: Int64;
    i, j: Integer;
    d: Double; b: Boolean; c: Char; p: Pointer;
    s: AnsiString;
begin
  { SCRATCH -- the motivating shape. `j` is a per-iteration counter, so every
    worker must have its own. Racy and short without the clause. }
  acc := 0;
  parallel(pdChunked) for i := 0 to N-1 reduction(+: acc) private(j) do
  begin
    j := 0;
    while j < 3 do begin acc := acc + 1; j := j + 1; end;
  end;
  WriteLn('SCRATCH ', acc);

  { TYPES -- one private of each scalar shape the clause accepts, all used as
    scratch inside the body. 2 for an even index and 1 for an odd one, plus
    Trunc(2.0)-2 = 0, so the total is a fixed 1.5*M. }
  acc := 0;
  parallel(pdChunked) for i := 0 to M-1 reduction(+: acc) private(j, d, b, c, p) do
  begin
    j := i; d := 2.0; b := (j and 1) = 0; c := 'A'; p := nil;
    if b then acc := acc + 2 else acc := acc + 1;
    if p <> nil then acc := acc + 1000000;
    if c <> 'A' then acc := acc + 1000000;
    acc := acc + Trunc(d) - 2;
  end;
  WriteLn('TYPES ', acc);

  { SEED -- one worker, one iteration, each private READ before it is written.
    The enclosing variables all hold a non-zero value, so a private that were
    the shared one (or were left uninitialised on a dirty frame) shows up here.
    Weights differ so the printed number names WHICH component failed. }
  j := 12345; d := 9.5; b := True; c := 'Z'; bad := 0;
  parallel(pdChunked, n 1) for i := 0 to 0 reduction(+: bad) private(j, d, b, c) do
  begin
    if j <> 0 then bad := bad + 1;
    if d <> 0.0 then bad := bad + 10;
    if b then bad := bad + 100;
    if c <> Char(0) then bad := bad + 1000;
  end;
  WriteLn('SEED ', bad);

  { STR -- a private MANAGED scratch string, which is the shape that had to be
    pinned to a single worker in test_setlen_in_parallel_for_body.pas because it
    could not be written race-free. Seeded to '' rather than left holding the
    enclosing handle: a private that shared the outer handle would race on its
    refcount, not merely on its value. }
  sacc := 0; s := 'OUTER';
  parallel(pdChunked) for i := 0 to NSTR-1 reduction(+: sacc) private(s) do
  begin
    s := '';
    SetLength(s, 8);
    s := 'ab';
    if Length(s) = 2 then sacc := sacc + 1;
  end;
  WriteLn('STR ', sacc);

  { the enclosing variables must be exactly as they were left: `private` writes
    nothing back, which is the whole difference from `reduction`. }
  WriteLn('OUTER ', j, ' ', d:0:1, ' ', b, ' ', c, ' <', s, '>');

  if (acc <> (M * 3) div 2) or (bad <> 0) or (sacc <> NSTR) then gbad := gbad + 1;
end;

begin
  gbad := 0;
  Run; Run; Run;
  if gbad = 0 then WriteLn('PARPRIV OK') else WriteLn('PARPRIV BAD ', gbad);
end.
