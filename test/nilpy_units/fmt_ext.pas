unit fmt_ext;
{ cpyext: the bridge NilPy binds for the PyErr_Format specifier probe.

  Pulls pxx's own Python.h-backed runtime and the driver that calls
  PyErr_Format / PyUnicode_FromFormat once per specifier shape. Each case's
  expected text is what real CPython 3.12 produces for the same call — see
  test/test_cpyext_errformat.npy.
  bug-cpyext-pyerr-format-prints-U-and-S-literally }

{$PYEXTENSION}
{ This unit is a Python EXTENSION MODULE, not an ordinary Pascal unit: NilPy
  reaches it with a bare `import fmt_ext`, the way CPython reaches every C
  accelerator. The directive is the record of that; the resolver checks it
  against the unit binding the cpyext runtime before honouring it.
  feature-n-a-cpyext-extension-module-is-bare-importable-not-a-pascal-unit }

interface

uses pxxcio, '../../lib/cpyext/src/pyruntime.c', './fmt_ext_host.c';

function fmtCase(which: Integer): AnsiString;
function fmtUnicode: AnsiString;

implementation

function fmtCase(which: Integer): AnsiString;
var buf: array[0..511] of Char;
begin
  if fmt_ext_case(which, @buf[0], 512) <> 0 then
    fmtCase := '<no such case>'
  else
    fmtCase := PCharToString(@buf[0]);
end;

function fmtUnicode: AnsiString;
var buf: array[0..511] of Char;
begin
  fmt_ext_unicode(@buf[0], 512);
  fmtUnicode := PCharToString(@buf[0]);
end;

end.
