unit strhelperprobe;
{ The smallest unit that puts sysutils' `TStringHelper = type helper for
  AnsiString` in scope. It needs no exported surface at all -- the `uses`
  clause IS the probe: once any imported unit pulls sysutils, every str-typed
  NilPy receiver has a Pascal string helper in scope, and the type-helper
  dispatch resolved four Python str spellings to the PASCAL method.

  A local unit rather than `import pathlib`, which also drags sysutils in:
  this way the test states its own precondition instead of depending on which
  stdlib module happens to use sysutils today.
  bug-n-a-later-wall-in-key-analysis-blocks-convertrawtext-and-songformatter }
interface

uses sysutils;

function HelperInScope: Boolean;

implementation

function HelperInScope: Boolean;
begin
  HelperInScope := True;
end;

end.
