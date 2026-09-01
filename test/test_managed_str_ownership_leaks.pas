{ DOES A FRESH MANAGED STRING GET RELEASED, on every backend and every call kind.

  IRNodeOwnsManagedStr answers "does this node hand over a +1 the consumer must
  release". It has FOUR arms -- a string BINOP, a direct call, a VIRTUAL call and
  an INDIRECT call -- and the cross backends each carried a hand-written copy
  that listed only the first two. A missing arm does not crash and does not print
  anything wrong: the result is retained a second time, the refcount never
  reaches zero, and the program leaks in proportion to how often the expression
  runs. Both bugs found before this test existed were caught by somebody reading
  a heap number, never by a test (see the ticket).

  HOW THIS FAILS. Compiled with -dPXX_ALLOC_CENSUS, the runtime prints exact
  allocation counters, and they are IDENTICAL across targets for the same
  program. The make rows therefore compare this program's census output against
  the x86-64 build of the same source -- so a backend that stops releasing shows
  up as a differing `frees=` and `live=`, with no .expected to drift.

  MEASURED when it was written (2026-09-01): before the fix, `s := fp(i)` over
  4000 iterations gave `frees=0 live=3799` on i386, arm32, aarch64, riscv32 AND
  xtensa, against x86-64's `frees=3797 live=2` -- every single allocation leaked
  on every cross target. The concat arm gave xtensa `frees=3657 live=7318`
  against riscv32's `live=2`.

  THE TWO CHECKS ARE NOT THE SAME CHECK. The cross-target rows catch a backend
  that DIVERGES; tools/assert_no_leak.sh catches a leak every backend SHARES,
  which a differential cannot see by construction. The Length arm below is
  exactly that case and is why both are wired.

  NOT covered here, deliberately: the VIRTUAL call arm. xtensa allocates twice
  per iteration for it and still leaks after the ownership fix, which is a
  separate defect with its own ticket -- wiring it now would pin a known-bad
  number as expected. }
program test_managed_str_ownership_leaks;
type TMakeFn = function(n: Integer): AnsiString;

var s: AnsiString; i, k: Integer; fp: TMakeFn;

function MakeStr(n: Integer): AnsiString;
begin
  MakeStr := 'a';
  if n < 0 then MakeStr := 'b';
end;

begin
  { the CONCAT arm: two direct-call results as operands }
  for i := 1 to 2000 do
    s := MakeStr(i) + MakeStr(i);
  Writeln('concat len=', Length(s));

  { the INDIRECT arm: a call through a procedural variable }
  fp := @MakeStr;
  for i := 1 to 2000 do
    s := fp(i);
  Writeln('indirect len=', Length(s));

  { the DISCARDED arm: a fresh result consumed by Length and never stored.
    tkLength is lowered inline by every backend -- emit the arg, deref, read
    [-8] -- and nothing there released the temporary, so this leaked one handle
    per evaluation on ALL SIX backends identically. That sameness is the point:
    the cross-target rows above compare each target against the x86-64 build and
    would have compared two equally wrong numbers, so this arm is the reason
    tools/assert_no_leak.sh exists beside them. }
  k := 0;
  for i := 1 to 2000 do
    k := k + Length(MakeStr(i));
  Writeln('discarded k=', k);
end.
