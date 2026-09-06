{ `q^.field` where q is a POINTER TO A POINTER to a record.

  FPC/Delphi apply ONE implicit dereference to a pointer used with `.`, so
  `q^.e` means `q^^.e`. pxx dropped that second step and built the field access
  over the POINTER, reading the field at an offset into the pointer VALUE --
  a silent wrong number, no diagnostic. `q^.e` printed the low half of an
  address where fpc prints 55.

  Explicit `q^^.e` was always correct, because the lvalue chain's own
  depth-aware walk reduces it to a record before any field lookup. Only the
  IMPLICIT step went through ResolveNodeRec, whose AN_DEREF arm enumerated the
  base kinds it accepted -- variable, field, address-of, index, cast, call --
  and had no arm for a base that is itself a deref. Two mechanisms answering
  "what record does this deref yield", and the enumerated one was short a case
  the walking one handles.

  ASSERT A LATE FIELD, NOT THE FIRST. Offset 0 is what a lost base resolves to,
  so a probe reading `.a` cannot tell a correct answer from a dropped deref --
  both produce *something*. `.e` at offset 16 is the discriminating one, and the
  record is deliberately 20 bytes so no value here can collide with a pointer
  width either.

  The DEPTH GATE is the other half and it has its own row: two implicit derefs
  (`z^.e` over a three-deep pointer) is "Illegal qualifier" under fpc 3.2.2, so
  resolving it would make us accept what FPC refuses. z^^.e -- one implicit step
  on a three-deep pointer -- is legal and must work.

  .expected IS fpc 3.2.2's own output on this source.
  bug-p-an-implicit-deref-over-an-explicit-caret-is-dropped }
program test_implicit_deref_through_a_pointer_to_pointer;
{$mode delphi}
type
  TRec = record a, b, c, d, e: Integer; end;
  PRec = ^TRec;
  PPRec = ^PRec;
  PPPRec = ^PPRec;
var
  r: TRec;
  p: PRec;
  q: PPRec;
  z: PPPRec;
begin
  r.a := 11; r.b := 22; r.c := 33; r.d := 44; r.e := 55;
  p := @r; q := @p; z := @q;

  WriteLn('1 ', p.e);        { single level, implicit -- always worked }
  WriteLn('2 ', p^.e);       { single level, explicit }
  WriteLn('3 ', q^^.e);      { two levels, both explicit -- always worked }
  WriteLn('4 ', q^.e);       { two levels, ONE implicit -- the bug }
  WriteLn('5 ', z^^^.e);     { three levels, all explicit }
  WriteLn('6 ', z^^.e);      { three levels, ONE implicit -- the bug }
  WriteLn('7 ', q^.a);       { first field too, so a base shift shows here }
  WriteLn('8 ', q^.c);
  WriteLn('OK');
end.
