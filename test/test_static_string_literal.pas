{ IS A STRING LITERAL HANDED OVER WITHOUT A HEAP COPY, on every backend.

  A literal is already a complete managed string in .data -- emit.inc writes the
  meta word, a saturated MSTR_STATIC_RC, an 8-byte length and the bytes, for
  every literal on every target. So `s := 'yy'` should allocate NOTHING.

  x86-64 has done that since the uforth profile put PXXStrFromLit at 9.28% of
  its runtime, and aarch64 followed. i386, arm32, riscv32 and xtensa had no such
  path at all: 2000 iterations of the loop below allocated 1871 times on each of
  them against ZERO on x86-64. Nothing leaked -- frees tracked allocs -- which is
  exactly why no existing check could see it. It was found by accident, sweeping
  an unrelated fix across targets.

  HOW THIS FAILS. Two checks, and they ask different questions.

  The CEILING row (tools/assert_alloc_ceiling.sh) is the subject: it fails if
  the literal loop starts allocating again. Part B below exists solely so the
  census has something to print -- a program that allocates nothing prints no
  census line, and a ceiling with no floor is a check that passes by measuring
  nothing. So the floor is deliberate and the ceiling sits far above it and far
  below the loop count.

  The DIFFERENTIAL row is correctness, and it is the one that matters more. The
  optimisation hands out a pointer INTO the literal pool. If a backend ever
  writes through that pointer, or lets the refcount be decremented to zero and
  the block reused, the output below changes and no allocation count would show
  it. Each part is a way that can happen:

    A  2000 assignments of one literal      -- the subject
    B  a deliberate allocator so the census speaks
    C  two variables from the SAME literal, one mutated -- if the block is
       shared and written through, both change
    D  5000 store/overwrite cycles -- each one releases the previous handle, so
       if the release path does not refuse to write a saturated block the static
       refcount walks down and the literal is eventually freed and reused
    E  the empty string, which Pascal collapses to nil while NilPy does not.
       Verified to be a real discrimination, not a formality: with the split
       deliberately disabled, part E printed emptynil=0 instead of 1.

  perf-a-every-string-literal-assignment-heap-copies-on-i386-arm32-riscv32-and-xtensa }
program test_static_string_literal;
var s, t, a, b: AnsiString; i, k: Integer;
begin
  { A -- the subject: this must not allocate }
  k := 0;
  for i := 1 to 2000 do
  begin
    s := 'yy';
    k := k + Length(s);
  end;
  Writeln('A lit k=', k);

  { B -- the deliberate floor, so the census line exists. The concat has to
    involve a RUNTIME value: `'x' + 'y'` is constant-folded to a literal and
    allocates once for the whole loop, which put the floor at 1 and left the
    ceiling resting on nothing. }
  t := '';
  for i := 1 to 150 do
    t := 'x' + Chr(65 + (i mod 26));
  Writeln('B floor len=', Length(t));

  { C -- sharing: one literal, two variables, one mutated }
  a := 'Alpha';
  b := 'Alpha';
  a[1] := 'x';
  Writeln('C a=', a, ' b=', b);

  { D -- the overwrite cycle: 5000 releases of a saturated block }
  for i := 1 to 5000 do
    s := 'persistent';
  b := 'persistent';
  Writeln('D s=', s, ' len=', Length(s), ' eq=', Ord(b = s));

  { E -- the empty-string split, read through the handle itself }
  s := '';
  Writeln('E emptynil=', Ord(Pointer(s) = nil));
  s := 'yy';
  Writeln('E litnil=', Ord(Pointer(s) = nil), ' v=', s);
end.
