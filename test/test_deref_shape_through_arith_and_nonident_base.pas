program test_deref_shape_through_arith_and_nonident_base;
{ What `^` yields, on the two spellings the deref walk could not answer.

  ResolveDerefShape knew more ABOUT each shape (remaining depth, ultimate base)
  and NodePtrElem knew more SHAPES, and neither was a superset -- so swapping a
  call site from one to the other traded one kind of knowledge for the other,
  silently. Rows 3 and 5 are the two spellings that had only the poorer answer:
  both printed a raw ADDRESS where a string belongs, on the pinned binary.

  Rows 1, 2 and 4 are the controls that must NOT move -- an integer and a byte
  through pointer arithmetic (the span is what a wrong pointee costs there) and
  an index over a plain variable, which always worked.
  refactor-a-two-predicates-answer-what-a-caret-yields }
type
  PPC  = ^PChar;
  PInt = ^Integer;
  PB   = ^Byte;
  TRec2 = record q: array[0..2] of PPC; end;
  PRec2 = ^TRec2;
var
  a: array[0..2] of PChar;
  ints: array[0..3] of Integer;
  bs: array[0..3] of Byte;
  pcs: array[0..2] of PPC;
  r2: TRec2;
  raw2: Pointer;
  pp: PPC; pi: PInt; pb: PB;
  s1, s2: PChar;
begin
  s1 := 'alpha'; s2 := 'beta';
  a[0] := s1; a[1] := s2; a[2] := s1;
  ints[0] := 10; ints[1] := 20; ints[2] := 30; ints[3] := 40;
  bs[0] := 1; bs[1] := 2; bs[2] := 3; bs[3] := 4;
  pp := @a[0]; pi := @ints[0]; pb := @bs[0];
  pcs[0] := @a[0]; pcs[1] := @a[1];
  r2.q[0] := @a[0]; r2.q[1] := @a[1];
  raw2 := @r2;
  writeln('1 ', (pi + 2)^);            { expect 30  -- ^Integer arithmetic }
  writeln('2 ', (pb + 3)^);            { expect 4   -- ^Byte arithmetic, span matters }
  writeln('3 ', (pp + 1)^);            { expect beta }
  writeln('4 ', pcs[1]^);              { expect beta -- index over an IDENT base }
  writeln('5 ', PRec2(raw2)^.q[1]^);   { expect beta -- index over a FIELD base }
end.
