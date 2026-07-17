program test_ansistring_cast_fnptr;
{ Regression: AnsiString(<call through a function-pointer returning PChar>) must
  strlen-copy. The proc-type signature ($proctype) previously dropped
  ProcRetPtrElemTk, so IsNodePChar could not tell an indirect call returned char*.
  See bug-pascal-ansistring-cast-of-fnptr-call-result. }
type TPCharFn = function(n: PAnsiChar): PAnsiChar; cdecl;
function setenv(n, v: PAnsiChar; o: Integer): Integer; cdecl; external 'libc.so.6';
function getenv(name: PAnsiChar): PAnsiChar; cdecl; external 'libc.so.6';
var fp: TPCharFn; s: AnsiString;
begin
  setenv('PXX_FNP_TEST', 'world', 1);
  fp := @getenv;
  s := AnsiString(fp('PXX_FNP_TEST'));
  writeln('fnptr=', s, ' len=', Length(s));
end.
