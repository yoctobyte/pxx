{ SPDX-License-Identifier: 0BSD }
{ An exception nobody catches on the ESP IDF profile PRINTS before the
  program parks: the same "Unhandled exception: <Class>: <Message>" line a
  hosted target writes. ESP has no kernel for the hosted raise stub's write, so
  until 2026-09-25 this parked with no output at all. The raise is inside a
  routine on purpose, so the report has to come from the main-body catch-all
  and not from anything at the raise site. The fixed .expected is not the
  x86-64 oracle, which writes the line to stderr. }
program test_esp_uncaught_exception_prints;
uses sysutils;

procedure Fail(n: Integer);
begin
  raise EConvertError.Create('bad value ' + IntToStr(n));
end;

begin
  writeln('before raise');
  Fail(42);
  writeln('after raise');
end.
