program test_ansistring_cast_extern_pchar;
{ Regression: AnsiString(<direct external cdecl PChar-returning call>) must
  strlen-copy, not reinterpret the pointer as a managed-string handle.
  Before the fix the external-decl path dropped ProcRetPtrElemTk, so
  IsNodePChar could not tell the call returned char*, and the cast produced a
  garbage length (heap over-read). See
  bug-pascal-ansistring-cast-of-cdecl-call-result. }
function setenv(name, val: PAnsiChar; overwrite: Integer): Integer; cdecl; external 'libc.so.6';
function getenv(name: PAnsiChar): PAnsiChar; cdecl; external 'libc.so.6';
var
  s: AnsiString;
  p: PAnsiChar;
begin
  setenv('PXX_CAST_TEST', 'hello', 1);

  { the previously-broken form: cast the call result directly }
  s := AnsiString(getenv('PXX_CAST_TEST'));
  writeln('direct=', s, ' len=', Length(s));

  { the form that always worked: via a variable }
  p := getenv('PXX_CAST_TEST');
  s := AnsiString(p);
  writeln('viavar=', s, ' len=', Length(s));
end.
