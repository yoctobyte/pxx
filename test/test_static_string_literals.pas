program test_static_string_literals;

{ At -O2 AND ABOVE a string literal that becomes a managed AnsiString is an
  ADDRESS into the data section, not a call to PXXStrFromLit that allocates and copies the
  same bytes on every evaluation. The block is built by the compiler
  (InternStr, emit.inc) with a saturated refcount, so nothing ever frees it and
  every write to it must copy first.

  This test is about the ways that can go wrong, and each one shows up as a
  WRONG VALUE rather than a crash:

    - the static block gets mutated in place, so the NEXT evaluation of the
      same literal reads someone else's edit;
    - the block gets appended into in place, same thing with room to spare;
    - the block gets freed, because the handle was handed out without the
      reference the old fresh-block convention implied;
    - the empty literal stops collapsing to nil the way a Pascal AnsiString
      must, or the ASCII flag stamped at compile time disagrees with the bytes.

  Every row therefore reads a literal AGAIN after something has been done to a
  copy of it, and the two answers are printed side by side. -O0 is the control:
  the pass is gated at `OptLevel < 2`, so -O0 provably cannot take the static
  path, and one expectation covers both. (This said "-O3-gated" for as long as
  that was false: 440c822e6a80 promoted the pass into -O2, which is why -O2 is
  in the Makefile's level list and is not redundant with -O3.)
  bug-o-uforth-blocktest-runs-slower-under-pxx-than-under-cpython }

var
  gAcc: Int64;

function Digest(const s: AnsiString): Int64;
{ Order-sensitive and length-sensitive, so a wrong byte, a short read and a
  stale tail are three different numbers. }
var i, h: Int64;
begin
  h := Length(s) * 7;
  for i := 1 to Length(s) do h := (h * 31 + Ord(s[i])) and $FFFFFFF;
  Digest := h;
end;

procedure ByValue(s: AnsiString);
{ A literal passed by value: the callee owns its own copy and grows it. If that
  growth lands in the caller's static block, the caller's next read of the same
  literal is wrong. }
begin
  s := s + '-tail';
  gAcc := gAcc + Digest(s);
end;

procedure Take(const s: AnsiString);
begin
  gAcc := gAcc + Digest(s);
end;

var
  a, b: AnsiString;
  i: Int64;

begin
  gAcc := 0;

  { 1. copy-on-write. `a[1] := ...` must copy, because the block is shared with
       every other evaluation of 'abcdef' in the program. }
  a := 'abcdef';
  a[1] := 'Z';
  b := 'abcdef';
  gAcc := gAcc + Digest(a) + Digest(b) * 3;
  writeln('cow a=', a, ' b=', b);

  { 2. append. PXXStrAppend may only extend a block in place when it allocated
       the spare capacity itself; a static block carries neither the flag nor a
       size word, and rc says shared besides. }
  a := 'abcdef';
  for i := 1 to 3 do a := a + 'z';
  b := 'abcdef';
  writeln('append a=', a, ' b=', b);
  gAcc := gAcc + Digest(a) + Digest(b) * 5;

  { 3. SetLength. The inlined resize has an in-place arm gated on rc = 1. }
  a := 'abcdef';
  SetLength(a, 3);
  b := 'abcdef';
  writeln('setlen a=', a, ' b=', b, ' len=', Length(b));
  gAcc := gAcc + Digest(a) + Digest(b) * 7;

  { 4. by-value parameter, then read the literal again. }
  ByValue('abcdef');
  b := 'abcdef';
  writeln('param b=', b);
  gAcc := gAcc + Digest(b) * 11;

  { 5. const parameter — no copy at all, the static handle goes straight in. }
  Take('abcdef');

  { 6. the empty literal still collapses to nil for a Pascal AnsiString, and
       comparing/appending to it behaves. }
  a := '';
  writeln('empty len=', Length(a), ' eq=', a = '', ' cat=', a + 'x');
  gAcc := gAcc + Length(a) + Digest(a + 'x') * 13;

  { 7. a high byte: the ASCII answer is stamped at compile time and must match
       the bytes, and the length must count BYTES. }
  a := 'ab' + chr(200) + 'cd';
  b := 'ab' + chr(200) + 'cd';
  writeln('high len=', Length(a), ' ord=', Ord(a[3]), ' eq=', a = b);
  gAcc := gAcc + Digest(a) * 17;

  { 8. the loop that would expose a refcount walking down: many store /
       overwrite cycles on one literal. If the handle is handed out without a
       reference, each cycle nets -1 on the static block's count, and the value
       read afterwards is whatever the freed memory became.

       The COUNT is not part of what this asserts, and could not be: the static
       refcount starts at 2^30, so no reachable number of iterations proves the
       reference is taken -- only a program that ran for minutes would, and this
       row is a smoke test for "the loop still works". Everything printed below
       is count-INDEPENDENT, which is why one expectation covers both arms and
       why lowering the emulated count is not a weakening.

       The count was briefly lowered for the emulated targets, because the
       static block's refcount word could land on the same 4 KiB page as
       translated code and a hot write there made a qemu-user-style emulator
       invalidate its translations on every store -- 83x on aarch64, 1600x on
       x86-64 under qemu-x86_64, for a binary that ran in 0.009s natively.
       That is fixed at the source: the ELF writer now pads code to a page
       boundary so the data section starts on a page of its own, and this
       subject runs in 0.32s on aarch64 under qemu against 91.69s without the
       padding (same HEAD, both arms rebuilt: f50ff77ecd42 vs a2701c58b005).
       The full count is back, because a workaround that outlives its cause is
       how a test quietly stops testing what its comment says it does.
       bug-a-a-hot-write-to-a-data-page-that-shares-with-code-costs-1600x-under-qemu }
  for i := 1 to 200000 do
  begin
    a := 'recycled';
    b := a;
    a := 'other';
  end;
  a := 'recycled';
  writeln('loop a=', a, ' len=', Length(a), ' b=', b);
  gAcc := gAcc + Digest(a) * 19 + Digest(b) * 23;

  writeln('acc=', gAcc);
  writeln('done');
end.
