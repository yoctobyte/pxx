unit textfile_unit_dep;
{ Helper unit exercising the classic Text file procedures with only `uses
  sysutils` — no explicit `uses textfile`. In FPC these live in System and are
  ambient in every unit; PXX must inject the implicit textfile RTL for a unit
  too (bug-textfile-primitives-not-ambient-in-units). }
interface
uses sysutils;
function RoundTrip(const path, payload: AnsiString): AnsiString;
implementation
function RoundTrip(const path, payload: AnsiString): AnsiString;
var f: Text; s: AnsiString;
begin
  Assign(f, path);
  Rewrite(f);
  writeln(f, payload);
  Close(f);
  Assign(f, path);
  Reset(f);
  readln(f, s);
  Close(f);
  RoundTrip := s;
end;
end.
