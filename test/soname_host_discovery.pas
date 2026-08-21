{ feature-dynamic-soname-discovery: `external 'lib<x>.so'` names a library the
  way source always spells it — unversioned. The loader wants the versioned
  soname (libgcc_s.so.1), and on a machine with only runtime packages the
  unversioned spelling is not a file at all: it is the -dev symlink.

  libgcc_s deliberately: it is NOT in the compiler's hardcoded eight-library
  table, so a versioned DT_NEEDED here can only have come from reading the host
  (/etc/ld.so.cache). Nothing is called — taking the address is enough to make
  the import real, and calling _Unwind_Backtrace for a test would be silly. }
program soname_host_discovery;

function _Unwind_Backtrace(trace, arg: Pointer): Integer; cdecl; external 'libgcc_s.so';

var p: Pointer;
begin
  p := @_Unwind_Backtrace;
  if p = nil then WriteLn('unexpectedly nil');
  WriteLn('soname discovery ok');
end.
