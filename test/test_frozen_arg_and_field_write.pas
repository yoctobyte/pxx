program test_frozen_arg_and_field_write;

{ Two i386 defects under -dPXX_SHORTSTRING, both invisible on x86-64 and both
  invisible in the DEFAULT mode:

  1. WriteLn of a record's `string[N]` FIELD was a compile error on i386
     ("target i386: write of this operand not yet supported"). The IR_WRITE
     frozen arm was spelled `tk = tyString`; a field load keeps its storage
     kind (tyShortString) where a plain variable normalises to tyString through
     StrValTk, so `WriteLn(s)` was correct beside `WriteLn(r.f)` refusing.
     bug-a-i386-refuses-a-frozen-record-field-write-under-the-byte-prefix-mode

  2. Passing a frozen string to a MANAGED string parameter resolved its prefix
     width from the IR_ARG node rather than the value node. An arg node is
     tagged tyString generically, so the answer was the 8-byte default every
     time: a one-byte prefix read as eight is a length in the billions, and
     PXXStrFromLit segfaulted. Copy() and Pos() are two callers of that
     conversion, not the subject.
     bug-a-i386-copy-and-pos-segfault-under-the-byte-prefix-mode

  WHY THE EXPECTED VALUES ARE LITERALS AND NOT AN x86-64 SELF-BUILD. Defect 2
  could not fail in the default mode: there the wrong answer (tyString, 8) and
  the right answer are the SAME kind, so a default-mode row is a guard that
  cannot fail. The flag is therefore mandatory here, and every row is asserted
  against a value the compiler had no hand in producing.

  ASSERT THE VALUE, NEVER Length(). On a 32-bit target a wrong-offset length
  read truncates into the right answer -- 0x20000000002 has low 32 bits of
  exactly 2 -- so a Length() probe passes on i386, arm32 and riscv32 with the
  bug fully present. The Length row below is present only as a companion to the
  content row, never instead of it. }

type
  R = record f: string[10]; g: string[4]; end;
  TA = array[0..1] of R;

var
  s, t: string[10];
  r: R;
  arr: TA;
  n: Integer;

procedure Show(const a: AnsiString);
{ A frozen argument onto a MANAGED parameter -- the conversion defect 2 broke.
  `const` does not change the marshalling: the callee's slot is a handle either
  way, so the caller still has to build one. }
begin
  WriteLn('<', a, '>');
end;

begin
  s := 'abcdef';
  r.f := 'field';
  r.g := 'gg';
  arr[1].f := 'elem';

  { the write arms: variable (always worked), field, second field, array elem }
  WriteLn('A[', s, ']');
  WriteLn('B[', r.f, '][', r.g, ']');
  WriteLn('C[', arr[1].f, ']');

  { the argument conversion, through a plain user routine }
  Show(s);

  { ...and through the two intrinsics that lower to helper calls }
  t := Copy(s, 2, 3);
  WriteLn('D[', t, ']');
  WriteLn('E[', Copy(s, 2, 3), ']');
  n := Pos('cd', s);
  WriteLn('F', n);

  { content beside length, in that order -- see the header }
  WriteLn('G', Length(r.f), '[', r.f, ']');

  { a comparison in BOTH directions: a frozen compare that fails by answering a
    CONSTANT is certified correct by a suite of must-be-TRUE rows alone }
  if r.f = 'field' then WriteLn('Hyes') else WriteLn('Hno');
  if r.f = 'nope' then WriteLn('Ibad') else WriteLn('Iok');

  { A frozen RECORD FIELD and an ARRAY-OF-RECORD ELEMENT as the argument, not a
    plain variable. This is the row x86-64 failed while every other target
    passed: its conversion guard said `= tyString`, and a field or element load
    keeps tyShortString where a variable normalises to tyString -- so the
    conversion was skipped entirely and the raw [len][chars] buffer went to the
    callee as a managed handle. It does not crash -- the callee reads a length
    from [handle-8], which is whatever happens to sit before the field -- so it
    answers a plausible wrong NUMBER. Measured against a rebuilt pre-fix x86-64
    compiler, these two rows came back J0 K0 against the correct J3 K1, under the
    flag only -- the default mode was right on every target. }
  WriteLn('J', Pos('el', r.f));
  WriteLn('K', Pos('el', arr[1].f));
end.
