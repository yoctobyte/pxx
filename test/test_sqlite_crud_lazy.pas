program test_sqlite_crud_lazy;
uses sqlite3, builtin;

procedure Exec(db: Pointer; sql: PChar);
begin
  var exec_rc := sqlite3_exec(db, sql, nil, nil, nil);
  if exec_rc <> 0 then writeln('exec failed rc=', exec_rc);
end;

begin
  var db := nil;
  var stmt := nil;

  var rc := sqlite3_open(PChar('/tmp/test_sqlite_crud_lazy26.db'), @db);
  writeln('open=', rc);

  Exec(db, PChar('DROP TABLE IF EXISTS t;'));
  Exec(db, PChar('CREATE TABLE t(id INTEGER, name TEXT);'));
  Exec(db, PChar('INSERT INTO t VALUES(1, ''alice'');'));
  Exec(db, PChar('INSERT INTO t VALUES(2, ''bob'');'));

  rc := sqlite3_prepare_v2(db, PChar('SELECT id, name FROM t ORDER BY id;'),
                           -1, @stmt, nil);
  writeln('prepare=', rc);

  while sqlite3_step(stmt) = 100 do   { 100 = SQLITE_ROW }
  begin
    var id := sqlite3_column_int(stmt, 0);
    var name := PCharToString(sqlite3_column_text(stmt, 1));
    var name2: string := sqlite3_column_text(stmt, 1);
    writeln(id, ' ', name, ' ', name2);
  end;

  rc := sqlite3_finalize(stmt);
  writeln('finalize=', rc);
  rc := sqlite3_close(db);
  writeln('close=', rc);
end.
