program test_weakexternal_absent;
{ `weakexternal` -- an OPTIONAL import, the ABSENT half.

  Two rows, and the second is the one that proves the mechanism rather than the
  spelling:

    nosuchfunc  a symbol no library anywhere defines. Declared `external` this
                is a fatal `symbol lookup error` before main runs -- asserted in
                the Makefile beside this test, because a program that cannot
                start cannot assert anything about itself.

    pthread_create  a symbol libc REALLY defines. It is nil here anyway, and
                that is the whole point: a library reached only by weak imports
                contributes no DT_NEEDED, so nothing loaded libc and there was
                nowhere to resolve it from. If DT_NEEDED were emitted, the
                loader would pull libc in to answer the question and this row
                would read `resolved` -- so this row, not the one above, is what
                fails if the suppression regresses.

  The Makefile asserts the DT_NEEDED count is zero directly.
  feature-a-optional-imports-an-undefined-weak-dynamic-symbol }
function nosuchfunc_pxx_probe(x: Integer): Integer; cdecl;
  weakexternal 'libc.so.6' name 'nosuchfunc_pxx_probe';
function pthread_create(t, attr, fn, arg: Pointer): Integer; cdecl;
  weakexternal 'libc.so.6' name 'pthread_create';
begin
  if @nosuchfunc_pxx_probe = nil then Writeln('nosuchfunc: nil')
  else Writeln('nosuchfunc: resolved');
  if @pthread_create = nil then Writeln('pthread_create: nil')
  else Writeln('pthread_create: resolved');
  Writeln('program started and ran');
end.
