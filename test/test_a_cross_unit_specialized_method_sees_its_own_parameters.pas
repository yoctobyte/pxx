program test_a_cross_unit_specialized_method_sees_its_own_parameters;
{ A GENERIC METHOD BODY IS RE-PARSED AS ITS DECLARING UNIT -- deliberately, so a
  template calling its own unit's private helper gets that helper and not the
  specializer's same-named one. Its PARAMETERS, its `Result` and its `Self` are
  allocated by the header path, BEFORE that switch, so they carried the
  SPECIALIZING unit instead.

  When the two units differ and the declaring one does not `uses` the
  specializing one -- a library unit wrapping another unit's generic, i.e. the
  ordinary direction -- the cross-unit visibility test then refused a method its
  own arguments:

    undefined variable (a)
    undefined variable (Result)
    undefined variable (Self)

  WHY IT LOOKED LIKE A `Self` BUG AND IS NOT. Method bodies are spliced at the
  cursor, so they are parsed in REVERSE declaration order; whichever method
  mentions Self is usually reached first, and the compile stops there. A LOCAL
  declared inside the body is fine, because it is allocated after the switch --
  so `Self` looked special and nothing else did. The fixture therefore puts each
  routine-scoped name in its OWN method, and keeps a field read as the control
  that always worked.

  AND IT WORKS FROM A PROGRAM, which is where every reduction starts. A program
  is not a unit, so the two identities never disagree. Only a UNIT specializing
  another UNIT'S template reaches this, which is why nothing found it for as
  long as the corpus rows were programs.

  Both sections of the wrapping unit specialize, because the interface and the
  implementation reach the splice by different paths.

  Oracle: fpc 3.2.2 prints all ten rows exactly as below. The pinned compiler
  refuses this program.
  bug-p-a-cross-unit-specialized-method-cannot-see-its-own-parameters }
{$mode objfpc}{$H+}
uses ugxpwrap;
begin
  RunIface;
  RunImpl;
end.
