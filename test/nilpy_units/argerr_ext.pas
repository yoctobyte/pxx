unit argerr_ext;
{ M2 "arguments and errors" milestone (feature-nilpy-cpyext-c-api-from-source):
  the runtime bridge a NilPy `import argerr_ext` binds to, widening M1's
  hello_ext to PyArg_ParseTuple/Py_BuildValue's common format letters
  ("i l d s s# O") and PyErr_SetString propagating into a NilPy `except`.

  Same not-named-after-the-unit precaution as hello_ext.pas: the module
  source is argerr_ext_module.c, not argerr_ext.c — a path-form `uses` keys
  its "already compiled" guard off bare basename, so a C file sharing this
  unit's own name would silently never load (see
  bug-c-uses-path-basename-collides-with-enclosing-unit-name; confirmed with
  --debug when M1 hit this the first time, not guessed). }

{$PYEXTENSION}
{ This unit is a Python EXTENSION MODULE, not an ordinary Pascal unit: NilPy
  reaches it with a bare `import argerr_ext`, the way CPython reaches every C
  accelerator. The directive is the record of that; the resolver checks it
  against the unit binding the cpyext runtime before honouring it.
  feature-n-a-cpyext-extension-module-is-bare-importable-not-a-pascal-unit }

interface

uses pxxcio, '../../lib/cpyext/src/pyruntime.c', './argerr_ext_module.c', './argerr_ext_host.c';

function scale(x: Integer; factor: Double): Double;
function shout(const word: AnsiString): AnsiString;
function prefix_len(const data: AnsiString): Integer;
function identity(x: Integer): Integer;
function check_positive(x: Integer): Integer;

implementation

function scale(x: Integer; factor: Double): Double;
begin
  scale := argerr_ext_scale(x, factor);
end;

function shout(const word: AnsiString): AnsiString;
var buf: array[0..255] of Char;
begin
  argerr_ext_shout(PChar(word), @buf[0], 256);
  shout := PCharToString(@buf[0]);
end;

function prefix_len(const data: AnsiString): Integer;
begin
  prefix_len := argerr_ext_prefix_len(PChar(data), Length(data));
end;

function identity(x: Integer): Integer;
begin
  identity := argerr_ext_identity(x);
end;

function check_positive(x: Integer): Integer;
var errbuf: array[0..255] of Char; rv: Integer;
begin
  rv := argerr_ext_check_positive(x, @errbuf[0], 256);
  if errbuf[0] <> #0 then
    raise Exception.Create(PCharToString(@errbuf[0]));
  check_positive := rv;
end;

end.
