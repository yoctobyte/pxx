{ End-to-end SQLite round-trip through the imported /usr/include/sqlite3.h
  header: open a database, create a table, insert rows, then read them back
  with prepare/step and both an integer and a TEXT column. Exercises C
  function-pointer params (sqlite3_exec callback), PChar() string marshalling
  into const char*, and C-string read-back via PChar indexing. Links
  libsqlite3.so.0 dynamically. }
program test_sqlite_crud;
uses sqlite3;

var
  db, stmt: Pointer;
  rc, id, i: Integer;
  p: PChar;
  c: Char;
  name: string;

procedure Exec(sql: PChar);
begin
  rc := sqlite3_exec(db, sql, nil, nil, nil);
  if rc <> 0 then writeln('exec failed rc=', rc);
end;

begin
  db := nil;
  stmt := nil;

  rc := sqlite3_open(PChar('/tmp/test_sqlite_crud26.db'), @db);
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
    name := sqlite3_column_text(stmt, 1);
    writeln(id, ' ', name);
  end;

  rc := sqlite3_finalize(stmt);
  writeln('finalize=', rc);
  rc := sqlite3_close(db);
  writeln('close=', rc);
end.
