program test_weakexternal_present;
{ `weakexternal` -- the PRESENT half, and the per-LIBRARY rule.

  The plain `external getpid` is what puts libc.so.6 in DT_NEEDED. The weak
  pthread_create then resolves off it and is callable -- the dependency was
  taken for another reason and an optional symbol may rely on it. That is the
  shape every real use has: a program links libc because it imports SDL or
  sqlite, and the optional symbol comes along.

  A weak symbol that no library defines stays nil even here, which separates
  "the loader resolved it" from "everything went global".
  feature-a-optional-imports-an-undefined-weak-dynamic-symbol }
function c_getpid: Integer; cdecl; external 'libc.so.6' name 'getpid';
function c_getppid: Integer; cdecl;
  weakexternal 'libc.so.6' name 'getppid';
function nosuchfunc_pxx_probe(x: Integer): Integer; cdecl;
  weakexternal 'libc.so.6' name 'nosuchfunc_pxx_probe';
begin
  if c_getpid > 0 then Writeln('real import: ok') else Writeln('real import: FAIL');
  if @c_getppid <> nil then
  begin
    if c_getppid > 0 then Writeln('weak sibling: resolved and callable')
    else Writeln('weak sibling: resolved but returned nonsense');
  end
  else Writeln('weak sibling: nil -- FAIL');
  if @nosuchfunc_pxx_probe = nil then Writeln('undefined weak: still nil')
  else Writeln('undefined weak: resolved -- FAIL');
end.
