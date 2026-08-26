{ %fail }
{ A diagnostic raised inside a SPECIALIZED generic body must name the file the
  TEMPLATE came from, not the file the specialization was spliced into.

  The line number always rode on the token and was right; the file rode on the
  token's INDEX, and a splice moves tokens from one file's index range into
  another's. So `in:` named the using file -- or, when that was the main source,
  printed nothing at all, which reads as "this error is in the file you typed".
  On corpus work the entire job is finding which line of 60k lines of
  third-party source will not compile, and a confidently wrong file name sends
  you to the wrong one every time. The right line made it worse, not better: it
  reads as precise.

  The error itself is deliberately trivial (an undefined name in the template
  body); what is asserted is the PROVENANCE line under it.
  bug-p-a-diagnostic-in-a-used-unit-names-the-wrong-source-file }
program test_diag_in_specialized_body_names_the_template_file_fail;

uses ugenericbad;

type
  TIntCell = specialize TCell<Integer>;

var
  c: TIntCell;
begin
  c := TIntCell.Create;
  WriteLn(c.Get);
end.
