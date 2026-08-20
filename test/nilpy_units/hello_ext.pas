unit hello_ext;
{ M1 "hello-ext" milestone (feature-nilpy-cpyext-c-api-from-source): the
  runtime bridge a NilPy `import hello_ext` binds to. Pulls pxx's own
  Python.h-backed runtime (lib/cpyext/src/pyruntime.c), the hand-written
  extension module in real CPython boilerplate shape (./hello_ext.c: a
  PyMethodDef table + PyModuleDef + PyInit_hello_ext), and the embedding-side
  driver that discovers PyInit_hello_ext and calls through the method table
  (./hello_ext_host.c).

  BLOCKED on bug-c-uses-path-basename-collides-with-enclosing-unit-name:
  `./hello_ext.c` shares this unit's own basename, so its body is silently
  never loaded (declarations appear only as unresolved externs). This is the
  platonic shape (module source named after the module, as any real
  extension's would be) — left as-is rather than renamed to dodge the bug.
  `make test-nilpy` skips this test until the bug is fixed.

  No special NilPy-side registration is needed for `add_one` to become
  callable as `hello_ext.add_one(x)`: unit scope is flat for a NilPy `import`
  (compiler/pyparser.inc — the same resolver as a Pascal `uses` clause), so an
  ordinary `interface function` here binds exactly like
  test/nilpy_units/fmtprobe.pas's `describe` does for
  test_nilpy_array_of_const_unit.npy. }

{$PYEXTENSION}
{ This unit is a Python EXTENSION MODULE, not an ordinary Pascal unit: NilPy
  reaches it with a bare `import hello_ext`, the way CPython reaches every C
  accelerator. The directive is the record of that; the resolver checks it
  against the unit binding the cpyext runtime before honouring it.
  feature-n-a-cpyext-extension-module-is-bare-importable-not-a-pascal-unit }

interface

uses pxxcio, '../../lib/cpyext/src/pyruntime.c', './hello_ext.c', './hello_ext_host.c';

function add_one(x: Integer): Integer;

implementation

function add_one(x: Integer): Integer;
begin
  add_one := hello_ext_add_one(x);
end;

end.
