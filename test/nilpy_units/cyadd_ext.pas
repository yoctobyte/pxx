unit cyadd_ext;
{ cpyext M5a (feature-nilpy-cpyext-c-api-from-source): the runtime bridge a
  NilPy `import cyadd_ext` binds to, for a CYTHON-GENERATED extension module.

  Pulls pxx's own Python.h-backed runtime (lib/cpyext/src/pyruntime.c),
  Cython 3.2.9's unmodified output for vendor/cyadd.pyx, and the embedding
  driver that runs PEP 489 module init and calls through the module dict.

  The two -D flags in the Makefile rule are load-bearing, not tuning — see
  test/nilpy_units/vendor/README.md. }

interface

uses pxxcio, '../../lib/cpyext/src/pyruntime.c', './vendor/cyadd_cython.c',
     './cyadd_ext_host.c';

function cyadd(a, b: Integer): Integer;
function cyfact(n: Integer): Integer;
{ M5b: keyword arguments through the vectorcall path, and the variadic
  PyObject_CallFunctionObjArgs form. cysub (not cyadd) is the keyword subject
  because subtraction is not commutative — see cyadd_ext_host.c. }
function cysub(a, b: Integer): Integer;
function cysubKw(a, b: Integer): Integer;
function cysubKwRev(a, b: Integer): Integer;
function cysubMixed(a, b: Integer): Integer;
function cysubBadKw(a: Integer): Integer;
function cyaddObjArgs(a, b: Integer): Integer;

implementation

function cyadd(a, b: Integer): Integer;
begin
  cyadd := cyadd_ext_add(a, b);
end;

function cyfact(n: Integer): Integer;
begin
  cyfact := cyadd_ext_fact(n);
end;

function cysub(a, b: Integer): Integer;
begin
  cysub := cyadd_ext_sub(a, b);
end;

function cysubKw(a, b: Integer): Integer;
begin
  cysubKw := cyadd_ext_sub_kw(a, b);
end;

function cysubKwRev(a, b: Integer): Integer;
begin
  cysubKwRev := cyadd_ext_sub_kw_rev(a, b);
end;

function cysubMixed(a, b: Integer): Integer;
begin
  cysubMixed := cyadd_ext_sub_mixed(a, b);
end;

function cysubBadKw(a: Integer): Integer;
var errbuf: array[0..255] of Char; rv: Integer;
begin
  rv := cyadd_ext_sub_badkw(a, @errbuf[0], 256);
  if errbuf[0] <> #0 then
    raise Exception.Create(PCharToString(@errbuf[0]));
  cysubBadKw := rv;
end;

function cyaddObjArgs(a, b: Integer): Integer;
begin
  cyaddObjArgs := cyadd_ext_add_objargs(a, b);
end;

end.
