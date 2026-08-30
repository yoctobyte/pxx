program test_cast_lvalue_suffix_siblings;
{ The LVALUE twin of test_cast_deref_chain_siblings.

  An alias-name typecast used as an ASSIGNMENT TARGET -- `PRec(raw)^... := v` --
  had its own postfix suffix walk, the sixth and last copy in the Pascal
  frontend, and it was the laggard on both axes at once:

    row b  its token set was [^ .] with no `[`, so a subscript after the field
           reported `Expected: :=, but got: [` -- while the identical RVALUE
           parsed. That is the same defect the RECORD-name cast twin already
           fixed (bug-p-a-record-cast-as-an-assignment-target-cannot-be-indexed);
           this is the alias-name sibling, which was never grepped for.

    row c  its `^` arm typed every level from the outer alias's immediate
           pointee and stamped no shape, so a second `^` never descended: the
           store landed at the WRONG ADDRESS, silently, and the target kept its
           old value.

  Rows a/d/e/f are the shapes that already worked and must keep working -- they
  are what hid the two above: depth-1 through an alias cast is the spelling
  lib/rtl actually uses (80+ sites), and it was correct all along. Row f is the
  PChar ADAPTER cast, which carries no alias row and so takes the fallback arm.

  Note on the evidence: on the pre-fix compiler row b is a COMPILE error, so
  this program never reaches row c there -- the parse error MASKS the silent
  one, and running this test against the baseline shows only the first defect.
  Row c was therefore measured on its own, as a program containing nothing but
  the double deref: pre-fix it printed the target's UNCHANGED value (the store
  went elsewhere, no diagnostic), post-fix it prints 99, and FPC prints 99.

  Every row diffed against FPC 3.2.2. }
type
  TIn  = record z: Integer; end;
  TRec = record a: array[0..3] of Integer; b: Integer; inr: TIn; end;
  PRec = ^TRec;
  PPRec = ^PRec;
var
  r, q: TRec;
  p: PRec;
  pp: PPRec;
  raw, raw2: Pointer;
  s: AnsiString;
begin
  r.a[0] := 7; r.b := 12345; r.inr.z := 0;
  p := @r; pp := @p; raw := p; raw2 := pp;

  PRec(raw)^.b := 55;
  WriteLn('a field         : ', r.b);

  PRec(raw)^.a[0] := 42;
  WriteLn('b field[i]      : ', r.a[0]);

  PPRec(raw2)^^.b := 99;
  WriteLn('c double deref  : ', r.b);

  PRec(raw)^.inr.z := 77;
  WriteLn('d nested field  : ', r.inr.z);

  q.a[0] := 8; q.b := 9; q.inr.z := 1;
  PRec(raw)^ := q;
  WriteLn('e bare deref    : ', r.a[0], ' ', r.b);

  s := 'hello';
  UniqueString(s);
  PChar(s)^ := 'J';
  WriteLn('f pchar adapter : ', s);
end.
