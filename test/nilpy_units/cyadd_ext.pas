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

implementation

function cyadd(a, b: Integer): Integer;
begin
  cyadd := cyadd_ext_add(a, b);
end;

function cyfact(n: Integer): Integer;
begin
  cyfact := cyadd_ext_fact(n);
end;

end.
