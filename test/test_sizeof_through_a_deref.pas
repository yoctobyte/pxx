{ `SizeOf` of a field reached through a POINTER DEREF.

  `SizeOf(r.A)` has been right since RecFieldByteSize was written
  (bug-p-sizeof-an-array-field-returns-the-element-size: an array field used to
  answer its ELEMENT size, so `Move(src.A, dst.A, SizeOf(src.A))` copied one
  element of four while every surrounding line read as correct).

  `SizeOf(p^.A)` did not go anywhere near that helper. A `^` anywhere in the
  operand routes SizeOf to its EXPRESSION path, and an array-valued node carries
  its element kind, so the answer was 4 where fpc says 16 — the identical
  failure, one construct over, straight into GetMem and Move. The ticket for it
  expected a PARSE error; by the time it was taken the dispatch had started
  accepting the operand and the loud failure had quietly become a wrong number.

  `SizeOf(p^)` over a pointer-to-RECORD was refused outright, while the same
  spelling over a pointer-to-ARRAY answered correctly — two halves of "the whole
  pointee" disagreeing.

  Every row is diffed against fpc 3.2.2, including the `plain` rows that were
  already right: the fix moves nothing onto a new path by accident only if both
  paths are pinned.

  bug-p-every-compile-time-intrinsic-hand-rolls-its-own-operand-parser }
program test_sizeof_through_a_deref;

type
  TIn = record u, v: Integer; end;
  TR  = record
    a: array[0..3] of Integer;
    b: Integer;
    s: TIn;
    m: array[1..2, 0..2] of Byte;
    d: array of Integer;
  end;
  PR = ^TR;

var
  p: PR;
  r: TR;
begin
  New(p);
  WriteLn('deref arr : ', SizeOf(p^.a));   { was 4 }
  WriteLn('deref sca : ', SizeOf(p^.b));
  WriteLn('deref rec : ', SizeOf(p^.s));   { was a refusal }
  WriteLn('deref nd  : ', SizeOf(p^.m));   { was 1 }
  WriteLn('deref dyn : ', SizeOf(p^.d));   { a handle, so pointer width }
  WriteLn('deref sub : ', SizeOf(p^.s.u)); { two levels down }
  WriteLn('deref whol: ', SizeOf(p^));     { was a refusal }
  WriteLn('plain arr : ', SizeOf(r.a));
  WriteLn('plain rec : ', SizeOf(r.s));
  WriteLn('whole     : ', SizeOf(r));
  Dispose(p);
end.
