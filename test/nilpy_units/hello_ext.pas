unit hello_ext;
{ M1 "hello-ext" milestone (feature-nilpy-cpyext-c-api-from-source): the
  runtime bridge a NilPy `import hello_ext` binds to. Pulls pxx's own
  Python.h-backed runtime (lib/cpyext/src/pyruntime.c), the hand-written
  extension module in real CPython boilerplate shape (./hello_ext_module.c: a
  PyMethodDef table + PyModuleDef + PyInit_hello_ext), and the embedding-side
  driver that discovers PyInit_hello_ext and calls through the method table
  (./hello_ext_host.c).

  The module source is NOT named hello_ext.c on purpose
  (bug-pascal-uses-path-form-basename-collides-with-unit-name, filed
  alongside this ticket): a path-form `uses './x.c'` resolves by basename
  only (extension stripped), so a C file sharing this unit's own name
  ("hello_ext") collides with the "already compiled" guard `ParseUsesUnitBody`
  sets for the enclosing unit itself — the .c file's body is silently never
  loaded (its declarations appear only as unresolved externs, CodePos -1;
  confirmed with `--debug`, not guessed). Renaming the module source
  sidesteps it for M1; the resolver bug is real and separately reported.

  No special NilPy-side registration is needed for `add_one` to become
  callable as `hello_ext.add_one(x)`: unit scope is flat for a NilPy `import`
  (compiler/pyparser.inc — the same resolver as a Pascal `uses` clause), so an
  ordinary `interface function` here binds exactly like
  test/nilpy_units/fmtprobe.pas's `describe` does for
  test_nilpy_array_of_const_unit.npy. }

interface

uses pxxcio, '../../lib/cpyext/src/pyruntime.c', './hello_ext_module.c', './hello_ext_host.c';

function add_one(x: Integer): Integer;

implementation

function add_one(x: Integer): Integer;
begin
  add_one := hello_ext_add_one(x);
end;

end.
