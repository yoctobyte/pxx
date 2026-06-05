program test_sqlite_crud_autotyped;
uses sqlite3, builtin;

var
  db: auto;
  stmt: auto;
  rc: auto;
  id: auto;
  name: auto;

procedure Init;
begin
  db := nil;
  stmt := nil;
end;

procedure Exec(sql: PChar);
var
  exec_rc: auto;
begin
  exec_rc := sqlite3_exec(db, sql, nil, nil, nil);
  if exec_rc <> 0 then writeln('exec failed rc=', exec_rc);
end;

begin
  Init;

  rc := sqlite3_open(PChar(':memory:'), @db);
  writeln('open=', rc);

  Exec(PChar('DROP TABLE IF EXISTS t;'));
  Exec(PChar('CREATE TABLE t(id INTEGER, name TEXT);'));
  Exec(PChar('INSERT INTO t VALUES(1, ''alice'');'));
  Exec(PChar('INSERT INTO t VALUES(2, ''bob'');'));

  rc := sqlite3_prepare_v2(db, PChar('SELECT id, name FROM t ORDER BY id;'),
                           -1, @stmt, nil);
  writeln('prepare=', rc);

  while sqlite3_step(stmt) = 100 do   { 100 = SQLITE_ROW }
  begin
    id := sqlite3_column_int(stmt, 0);
    name := PCharToString(sqlite3_column_text(stmt, 1));
    writeln(id, ' ', name);
  end;

  rc := sqlite3_finalize(stmt);
  writeln('finalize=', rc);
  rc := sqlite3_close(db);
  writeln('close=', rc);
end.
