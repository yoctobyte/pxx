unit markupsafe_ext;
{ M4 "a real extension from PyPI" milestone
  (feature-nilpy-cpyext-c-api-from-source): the runtime bridge a NilPy
  `import markupsafe_ext` binds to, fronting a REAL, unmodified, vendored
  PyPI extension (test/nilpy_units/vendor/_speedups.c — MarkupSafe 3.0.3's
  own upstream filename, unrenamed, BSD-3-Clause, see vendor/README.md)
  rather than a hand-written toy like M1-M3's. Compiled by cfront against
  lib/cpyext/include/Python.h, whose M4 additions
  (PyUnicode_KIND/*_DATA/GET_LENGTH/IS_ASCII/New, METH_O, PyModuleDef_Slot +
  PyModuleDef_Init) exist because THIS extension's real source needed them —
  see the M4 comment atop Python.h. }

interface

uses pxxcio, '../../lib/cpyext/src/pyruntime.c', './vendor/_speedups.c', './markupsafe_ext_host.c';

function escape(const s: AnsiString): AnsiString;

implementation

function escape(const s: AnsiString): AnsiString;
var buf: array[0..511] of Char;
begin
  markupsafe_ext_escape(PChar(s), @buf[0], 512);
  escape := PCharToString(@buf[0]);
end;

end.
