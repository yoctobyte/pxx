program test_sizeof_string_matches_storage;
{ SizeOf(<type name>) must agree with SizeOf(<variable of that type>).

  The sibling of test_sizeof_real_matches_storage.pas, and the same defect one
  type over: two tables answered "what is a bare `string`", and only the
  declaration path asked BareStringKind. BuiltinTypeNameTk -- the table SizeOf
  consults -- hard-wired tyString, whose TypeSize is a literal 8, while a
  `string` variable, record field and array element every one of them occupied
  TARGET_PTR_SIZE. So on i386, arm32 and riscv32 the compiler contradicted
  itself inside one program: SizeOf(string) = 8, SizeOf(v) = 4. A wrong size
  handed to GetMem and Move, silently, on the targets where a four-byte overrun
  is least likely to be noticed.

  Like its sibling, THIS TEST CANNOT FAIL ON x86-64, where the hardcoded 8 and
  the pointer width coincide -- which is exactly how the bug survived. It is
  here as the portable half: the identity is what regressed, so asserting it on
  every target the suite can execute is what keeps the two tables unified. The
  cross-target half is measured in the ticket, on five targets.

  Row f is the double-case guard. `AnsiString` is the arm immediately BELOW
  `string` in the same chain and it always consulted the define correctly; the
  two arms agreeing is the property that was violated, so it is asserted rather
  than assumed.

  Checked against FPC 3.2.2 ({$MODE OBJFPC}{$H+}): SizeOf(string) = SizeOf(Pointer).
  bug-p-sizeof-string-disagrees-with-the-storage-string-actually-gets }

type
  TA4 = array[0..3] of string;
  TRS = record s: string; end;

var
  v: string;
  a: TA4;
  p, q: ^string;

begin
  { the regression itself: name and variable must agree }
  WriteLn('a ', SizeOf(string), '|', SizeOf(v));

  { pointer-sized BY DEFINITION -- a managed handle, on every target }
  WriteLn('b ', SizeOf(string) = SizeOf(Pointer));

  { an array of string must stride by exactly that same size -- the consumer
    that would have walked off the end when the two disagreed }
  WriteLn('c ', SizeOf(TA4) = 4 * SizeOf(v));

  { and so must a record field }
  WriteLn('d ', SizeOf(TRS) = SizeOf(v));

  { the stride the HARDWARE actually uses, which is the one that decides
    whether a Move overruns }
  p := @a[0];
  q := @a[1];
  WriteLn('e ', (PtrUInt(q) - PtrUInt(p)) = PtrUInt(SizeOf(string)));

  { the neighbouring arm of the same chain must give the same answer }
  WriteLn('f ', SizeOf(AnsiString) = SizeOf(string));

  WriteLn('OK');
end.
