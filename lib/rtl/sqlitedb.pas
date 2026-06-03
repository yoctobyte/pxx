unit sqlitedb;

{ Pointer-free SQLite facade for pointer-less frontends (Nil Python).

  Why this lives in Pascal and not C: the facade's job is translating between
  the C ABI and PXX-native types. Only Pascal is fluent in both — it speaks the
  C pointer ABI (via the imported sqlite3 header) AND can manufacture a managed
  `string` for return values (db_col_str), which a C binding cannot. Pascal
  callers do not need this unit; they call the raw header directly.

  v1 keeps the connection and the active statement in module globals, so a
  caller never holds a pointer-shaped value. Single connection, single active
  statement at a time — enough to prove an end-to-end CRUD round-trip.

  Dialect notes (see lib/rtl/builtin.pas): plain functions use Result; strings
  are built by concatenation; a string argument auto-marshals to a C
  `const char*` (length-prefix skipped) when the parameter is a Pointer, so no
  PChar() cast is needed on the way in; a PChar is indexed to read a returned C
  string on the way back. }

interface

uses sqlite3;

function  db_open(const path: string): Integer;
function  db_exec(const sql: string): Integer;
function  db_query(const sql: string): Integer;
function  db_step: Boolean;
function  db_col_int(col: Integer): Integer;
function  db_col_str(col: Integer): string;
function  db_query_done: Integer;
function  db_close: Integer;

implementation

const
  SQLITE_ROW = 100;   { sqlite3_step: a row is available }

var
  gDb:   Pointer;     { active connection }
  gStmt: Pointer;     { active prepared statement }

function db_open(const path: string): Integer;
begin
  gDb := nil;
  gStmt := nil;
  Result := sqlite3_open(path, @gDb);
end;

function db_exec(const sql: string): Integer;
begin
  Result := sqlite3_exec(gDb, sql, nil, nil, nil);
end;

function db_query(const sql: string): Integer;
begin
  gStmt := nil;
  Result := sqlite3_prepare_v2(gDb, sql, -1, @gStmt, nil);
end;

function db_step: Boolean;
begin
  Result := sqlite3_step(gStmt) = SQLITE_ROW;
end;

function db_col_int(col: Integer): Integer;
begin
  Result := sqlite3_column_int(gStmt, col);
end;

function db_col_str(col: Integer): string;
var
  p: PChar;
  i: Integer;
  c: Char;
begin
  Result := '';
  p := sqlite3_column_text(gStmt, col);
  i := 0;
  c := p[i];
  while c <> #0 do
  begin
    Result := Result + c;
    i := i + 1;
    c := p[i];
  end;
end;

function db_query_done: Integer;
begin
  if gStmt <> nil then Result := sqlite3_finalize(gStmt)
  else Result := 0;
  gStmt := nil;
end;

function db_close: Integer;
begin
  Result := sqlite3_close(gDb);
  gDb := nil;
end;

end.
