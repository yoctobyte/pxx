{ A unit with BOTH an initialization and a finalization section, used by
  test_shared_lib_init.pas. It is a separate file because a Pascal PROGRAM
  cannot carry a finalization section and a unit can, and DT_FINI is only
  observable through one.

  bug-a-c-a-shared-library-never-runs-its-initialisation }
unit usharedmark;

interface

var
  UnitInitRan: Integer;

implementation

initialization
  UnitInitRan := 7;

finalization
  { Printed, not stored: at DT_FINI time the host is about to drop the mapping,
    so a variable the host could read afterwards is exactly what does not
    survive. Standard output does. }
  WriteLn('shared-fini-ran');

end.
