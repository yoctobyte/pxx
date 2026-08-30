program test_generic_error_location_names_a_third_file_fail;
{ MUST NOT COMPILE — and the point is WHERE it says the error is.

  uerrtmpl.pas declares `generic TBox<T>` whose method body names a type that
  does not exist. uerrinst.pas specializes it, which is what forces that body
  to be checked. So there is exactly one error site in the whole program:
  uerrtmpl.pas line 22.

  The bug (bug-p-a-specialized-body-reports-errors-in-the-wrong-file) is that
  the diagnostic pairs the LINE NUMBER from the template's file with the
  FILE NAME of whatever unit the parser is currently in — two independent
  sources that only agree when the template and the specialization live in the
  same file. Cross-unit they never agree, and the pair names a location that
  contains neither the symbol nor anything related to it.

  Measured on binary d5a35c8de13a, before the fix:

      pascal26:22: error: unknown type: TNoSuchTypeAnywhere
        in: uerrinst.pas          <-- WRONG FILE; line 22 there is a comment

  The units are built so this cannot be a coincidence: uerrinst.pas is padded
  so that its own line 22 is `{ line 22 of uerrinst.pas: NOT the error site }`.
  A test that only asserted "an error occurs" would pass today, which is why
  the Makefile recipe greps the `in:` line and not the message. }
{$mode objfpc}
uses
  uerrinst;

var
  b: TIntBox;
begin
  b := MakeBox;
  b.Fill(7);
  WriteLn(b.Val);
end.
