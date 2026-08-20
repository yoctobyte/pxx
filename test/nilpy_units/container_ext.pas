unit container_ext;
{ M3 "strings and containers" milestone (feature-nilpy-cpyext-c-api-from-source):
  the runtime bridge a NilPy `import container_ext` binds to. Widens M1/M2's
  scalar-only extensions to list/tuple/dict construction + iteration
  (PyList_*/PyDict_*, PyDict_Next) and a str-distinct PyBytes_* round-trip,
  all exercised INSIDE the extension's own C code — see the scope note atop
  container_ext_module.c and lib/cpyext/include/Python.h's M3 comment for why
  this milestone does not yet surface a native NilPy list/dict.

  Same not-named-after-the-unit precaution as hello_ext.pas/argerr_ext.pas:
  the module source is container_ext_module.c, not container_ext.c (see
  bug-c-uses-path-basename-collides-with-enclosing-unit-name). }

{$PYEXTENSION}
{ This unit is a Python EXTENSION MODULE, not an ordinary Pascal unit: NilPy
  reaches it with a bare `import container_ext`, the way CPython reaches every C
  accelerator. The directive is the record of that; the resolver checks it
  against the unit binding the cpyext runtime before honouring it.
  feature-n-a-cpyext-extension-module-is-bare-importable-not-a-pascal-unit }

interface

uses pxxcio, '../../lib/cpyext/src/pyruntime.c', './container_ext_module.c', './container_ext_host.c';

function sum_range(n: Integer): Integer;
function join_lengths(const csv: AnsiString): AnsiString;
function char_histogram(const s: AnsiString): AnsiString;
function bytes_roundtrip(const data: AnsiString): AnsiString;

implementation

function sum_range(n: Integer): Integer;
begin
  sum_range := container_ext_sum_range(n);
end;

function join_lengths(const csv: AnsiString): AnsiString;
var buf: array[0..255] of Char;
begin
  container_ext_join_lengths(PChar(csv), @buf[0], 256);
  join_lengths := PCharToString(@buf[0]);
end;

function char_histogram(const s: AnsiString): AnsiString;
var buf: array[0..255] of Char;
begin
  container_ext_char_histogram(PChar(s), @buf[0], 256);
  char_histogram := PCharToString(@buf[0]);
end;

function bytes_roundtrip(const data: AnsiString): AnsiString;
var buf: array[0..299] of Char;
begin
  container_ext_bytes_roundtrip(PChar(data), Length(data), @buf[0], 300);
  bytes_roundtrip := PCharToString(@buf[0]);
end;

end.
