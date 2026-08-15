program test_scope_hiding_types;
{ Scope hiding — the LAST unit named in a `uses` clause wins — reaches every
  name table, not just routines.

  The rule shipped 2026-08-10 for PROCEDURES (bug-p-uses-order-does-not-decide-
  which-unit-wins) and reached types not at all: classes went through
  FindUClass, plain aliases through FindTypeAlias, enums through FindEnumType
  and named arrays through FindArrayType, and every one of those returned the
  FIRST row of the name whatever unit declared it. So ONE program answered
  ROUTINE-B and CLASS-A.

  Every expectation below is what FPC 3.2.2 prints for the same two units.
  bug-p-scope-hiding-covers-routines-but-not-types-and-classes }

uses shd_unit_a, shd_unit_b;

var
  t: TShdThing;
  a: TShdAlias;
  r: TShdRec;
  arr: TShdArr;
begin
  WriteLn('routine ', ShdWho);
  t := TShdThing.Create;
  WriteLn('class ', t.W);
  WriteLn('const ', ShdName);
  WriteLn('alias ', SizeOf(a));
  WriteLn('rec ', SizeOf(r));
  WriteLn('arr ', SizeOf(arr) div SizeOf(Integer));
  WriteLn('enum ', Ord(High(TShdEnum)));
end.
