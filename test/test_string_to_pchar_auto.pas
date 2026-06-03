{ Same SQLite round-trip as test_sqlite_crud.pas, but passes bare Pascal
  string literals to the const char* parameters with NO explicit PChar()
  cast. Proves automatic string -> const char* marshalling at the call site:
  a string argument to a Pointer parameter gets the +8 length-prefix skip the
  PChar() cast used to require. The C-string read-back side still uses PChar
  indexing (that is the opposite direction). Links libsqlite3.so.0. }
program test_string_to_pchar_auto;
uses sqlite3;

var
  db, stmt: Pointer;
  rc, id, i: Integer;
  p: PChar;
  c: Char;
  name: string;

procedure Exec(sql: string);
begin
  rc := sqlite3_exec(db, sql, nil, nil, nil);
  if rc <> 0 then writeln('exec failed rc=', rc);
end;

begin
  db := nil;
  stmt := nil;

  rc := sqlite3_open('/tmp/test_string_to_pchar_auto26.db', @db);
  writeln('open=', rc);

  Exec('DROP TABLE IF EXISTS t;');
  Exec('CREATE TABLE t(id INTEGER, name TEXT);');
  Exec('INSERT INTO t VALUES(1, ''alice'');');
  Exec('INSERT INTO t VALUES(2, ''bob'');');

  rc := sqlite3_prepare_v2(db, 'SELECT id, name FROM t ORDER BY id;',
                           -1, @stmt, nil);
  writeln('prepare=', rc);

  while sqlite3_step(stmt) = 100 do   { 100 = SQLITE_ROW }
  begin
    id := sqlite3_column_int(stmt, 0);
    p := sqlite3_column_text(stmt, 1);
    name := '';
    i := 0;
    c := p[i];
    while c <> #0 do
    begin
      name := name + c;
      i := i + 1;
      c := p[i];
    end;
    writeln(id, ' ', name);
  end;

  rc := sqlite3_finalize(stmt);
  writeln('finalize=', rc);
  rc := sqlite3_close(db);
  writeln('close=', rc);
end.
