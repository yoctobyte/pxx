{ feature-p-a-pascal-library-unit-does-not-parse — `library` + `exports`.

  The point is not that it parses; it is that the declared surface AGREES with
  what the object writer emits. `ObjProcIsExported` is `ProcCdecl and not
  ProcCStaticLink` and always was, so this file must produce exactly the object
  a `program` with the same three `cdecl` routines produces — the Makefile links
  it against library_exports_host.c and checks the answers, which is the only
  assertion that can tell a real export from a symbol that merely has the name.

  `Hidden` is here to be ABSENT: it is not in the exports clause and it is not
  `cdecl`, so it must stay a LOCAL symbol. Without it the test would pass on a
  compiler that exported everything. }
library test_library_exports;

function PxxLibAdd(a, b: Integer): Integer; cdecl;
begin
  PxxLibAdd := a + b;
end;

function PxxLibMul(a, b: Integer): Integer; cdecl;
begin
  PxxLibMul := a * b;
end;

{ Declared cdecl and exported by a SECOND clause, above the routine it names —
  FPC puts `exports` wherever it likes, and validation runs after both parse
  passes so that has to work. }
exports PxxLibNegate;

function Hidden(a: Integer): Integer;
begin
  Hidden := a - 1;
end;

function PxxLibNegate(a: Integer): Integer; cdecl;
begin
  PxxLibNegate := -a - Hidden(1);
end;

exports PxxLibAdd, PxxLibMul;

begin
end.
