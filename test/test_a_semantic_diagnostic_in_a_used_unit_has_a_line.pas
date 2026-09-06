{ A SEMANTIC DIAGNOSTIC RAISED INSIDE A `uses`d UNIT MUST NAME A LINE.

  `ASTLine` was zero for every node in an appended unit — a DWARF decision, and
  a correct one: the Pascal RTL, pylib and the unit bodies nobody wants to step
  through must contribute no rows or the whole runtime lands in the line table.
  But `ErrorAt`/`ErrorAtRecover` take the same field, and `ErrorPrintAt` drives
  the `pascal26:<n>:` prefix off it, so every semantic error inside a unit came
  out as `pascal26:0:`. Corpus work is ENTIRELY used units: fcl-passrc's
  pastree.pp is 5947 lines and reported one real defect with no coordinate at
  all.

  THE ASSERTION IS THE COORDINATE, NOT THE MESSAGE, and that distinction is the
  fixture. The text was always correct — a row asserting it passed throughout
  the defect. Only the line number can fail.

  BOTH POSITIONS ARE IN ONE RUN. The same statement (`r := p` for a record `r`)
  sits at line 18 of test/pascal_units/unit_a_semantic_error_in_a_unit.pas and
  at line 30 below; the main-file spelling always worked and is the control that
  says the fix did not simply hardcode something. Split across two rows in two
  files, the unit row prints a plausible number on its own.

  A PARSE error cannot see this defect — it is reported off the lexer's own
  position, which was never lost — so the offending statement has to be one that
  fails during LOWERING. bug-a-a-semantic-diagnostic-in-a-used-unit-has-no-location-at-all }
program test_a_semantic_diagnostic_in_a_used_unit_has_a_line;
type TR = record a, b: Integer; end;
var r: TR; p: Pointer;
begin
  p := nil;
  r := p;
  WriteLn(r.a);
end.
