unit strhelperprobe;
{ The smallest unit that pulls sysutils in beside a NilPy module, so a str
  method call is compiled with a Pascal unit imported rather than standing
  alone.

  IT IS NOT WHAT PUTS THE HELPER IN SCOPE, and this comment said it was until
  2026-09-09: a unit's `uses` does not re-export to its consumers, in fpc or
  here. The importing MODULE has to name sysutils itself, which
  test_nilpy_str_method_vs_pascal_string_helper.npy now does. The old claim read
  true only because FindHelperForType had no visibility test at all, so any
  helper anywhere answered; f0aca9c59 gave it one.
  regression-test-nilpy-test-nilpy-str-method-vs-pascal-string-helper

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
