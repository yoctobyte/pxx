{ A .so MUST RUN ITS INITIALISATION, and until 2026-09-01 none did.

  A shared library has no ELF entry point by design -- the loader is meant to be
  told about initialisers through the dynamic section instead, and elfwriter.inc
  emitted no DT_INIT and no .init_array, so the global initialisers, the unit
  initialization sections and the program body were all compiled into the image
  with nothing able to reach them. Every piece of pre-main state stayed unset:
  a library whose body did `Flag := 4242` exported a GetFlag that returned 0.
  Found by frankC, measured against a gcc dlopen host on both frontends.

  WHY test_shared_lib.pas COULD NOT CATCH THIS, which is the part worth
  remembering. Its program body is EMPTY, and carries a comment saying "No
  initialisation runs when a foreign program loads this library ... nothing
  above may depend on the main body. It is empty to say so." I wrote that. It
  documented the defect as if it were the design, so the test was built to avoid
  the one thing that was broken -- worse than an untested path, because the next
  reader takes it for a decision and stops looking. That comment is corrected in
  the same commit as this file.

  THE THREE THINGS ASSERTED HERE, because they fail independently:

    GetUnitInit   a unit's initialization section ran      (7)
    GetFlag       the program's own body ran               (4242)
    GetOrder      the unit ran BEFORE the body             (1)

  The third is not decoration. Initialisers are ordered -- a unit is fully
  initialised before the program that uses it -- and a DT_INIT that ran the body
  alone, or ran them in the wrong order, would satisfy the first two rows in
  isolation. The whole defect class here is "something that should have run
  did not", so an ordering that is merely plausible is what it looks like.

  Finalisation is asserted from the HOST side (the Makefile row watches for
  `shared-fini-ran` around dlclose): there is no DT_FINI in a pre-fix image
  either, so it is the same gap and the same fix, and at DT_FINI time the
  mapping is going away -- output survives that, a variable does not.

  bug-a-c-a-shared-library-never-runs-its-initialisation }
program test_shared_lib_init;
{$mode objfpc}{$H+}

uses
  usharedmark;

var
  Flag: Integer;
  Order: Integer;

{ The library's own state, set by the program body below. }
function GetFlag: Integer; cdecl;
begin
  GetFlag := Flag;
end;

{ The USED UNIT's state, set by its initialization section. }
function GetUnitInit: Integer; cdecl;
begin
  GetUnitInit := usharedmark.UnitInitRan;
end;

{1 when the unit's initialization had already run by the time the program body
  did, 0 when the body ran first or alone. }
function GetOrder: Integer; cdecl;
begin
  GetOrder := Order;
end;

begin
  if usharedmark.UnitInitRan = 7 then Order := 1 else Order := 0;
  Flag := 4242;
end.
