{ SpecializeToBuffer rewrites every token spelled like the template name to the
  specialization's name. A token immediately after a `.` is a member selector or
  a unit qualifier, and NEITHER can name the specialization -- so rewriting it
  captured names that had nothing to do with the generic.

  Two rows, because the defect wears two hats and only one of them is obvious:

    row 1  a FIELD spelled like the generic ROUTINE. `Result := aArg.Test`
           inside `generic function Test<T>` became `aArg.Test_TTestGlobal` ->
           `"Test_TTestGlobal": no such member on this record/class`.
    row 3  a UNIT-QUALIFIED type spelled like the generic CLASS.
           `P: uspecdotname.TBox` inside `generic TBox<T>` was rewritten to this
           specialization, so the plain record's field vanished ->
           `"Tag": no such member on this record/class`.

  ROW 2 IS THE CONTROL AND IS THE POINT OF THE FILE: the identical program with
  the field renamed `Fld` was ALWAYS correct. The rename being the only
  difference between rows 1 and 2 is what makes this the lookup and not the
  record -- without row 2, row 1 alone is equally consistent with the record
  being wrong.

  ROW 4 IS HERE BECAUSE THE FIRST CUT OF THE FIX BROKE IT AND THIS FILE COULD NOT
  SEE IT. A generic method's IMPLEMENTATION HEADER puts the template name after a
  dot as well --

    generic class function TTest.Add<T>(aLeft, aRight: T): T;

  -- and there the name IS the routine being defined and MUST be rewritten.
  Skipping it cost four conformance rows (tgenfunc3/4/9/12, all `unresolved
  forward: TTest.Add_LongInt`) while `gate.sh quick` stayed GREEN, because
  nothing in the quick tier declared a generic method out of line. It does now:
  that is what row 4 is for, and it is the row to keep if this file is ever
  trimmed.

  A qualified TYPE is not a fourth reading, checked rather than assumed: fpc
  refuses `specialize uspecdotname.TBox<T>` outright -- `Type identifier
  expected` / `Syntax error, "<" expected but "." found`. }
program test_specialization_does_not_rename_after_a_dot;
{$mode objfpc}
uses uspecdotname;

type
  TRecTest = record Test: LongInt; end;   { field spelled like the routine below }
  TRecFld  = record Fld:  LongInt; end;   { the control }

generic function Test<T>(aArg: T): LongInt;
begin
  Result := aArg.Test;
end;

generic function Ctl<T>(aArg: T): LongInt;
begin
  Result := aArg.Fld;
end;

type
  generic TBox<T> = class
    V: T;
    P: uspecdotname.TBox;                 { unit-qualified, spelled like the template }
  end;

  { row 4: a generic method declared IN the class and implemented OUT OF LINE,
    so its header spells the template name after a dot and MUST be rewritten }
  TOut = class
    generic class function Add<T>(aLeft, aRight: T): T;
  end;

generic class function TOut.Add<T>(aLeft, aRight: T): T;
begin
  Result := aLeft + aRight;
end;

var
  rt: TRecTest;
  rf: TRecFld;
  b: specialize TBox<LongInt>;
begin
  rt.Test := 42;
  Writeln('field ', specialize Test<TRecTest>(rt));
  rf.Fld := 42;
  Writeln('ctl   ', specialize Ctl<TRecFld>(rf));
  b := specialize TBox<LongInt>.Create;
  b.V := 7; b.P.Tag := 9;
  Writeln('unitq ', b.V, ' ', b.P.Tag);
  Writeln('outofl ', TOut.specialize Add<LongInt>(2, 3));
end.
