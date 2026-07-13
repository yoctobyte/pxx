program test_sqlite_crud_lazy;
uses sqlite3, builtin;

procedure Exec(db: Pointer; const sql: string);
begin
  var exec_rc := sqlite3_exec(db, sql, nil, nil, nil);
  if exec_rc <> SQLITE_OK then writeln('exec failed rc=', exec_rc);
end;

procedure RunTest(const DbPath: string);
begin
  var db := nil;
  var stmt := nil;

  var rc := sqlite3_open(DbPath, @db);
  writeln('open=', rc);

  Exec(db, 'DROP TABLE IF EXISTS t;');
  Exec(db, 'CREATE TABLE t(id INTEGER, name TEXT);');
  Exec(db, 'INSERT INTO t VALUES(1, ''alice'');');
  Exec(db, 'INSERT INTO t VALUES(2, ''bob'');');

  rc := sqlite3_prepare_v2(db, 'SELECT id, name FROM t ORDER BY id;',
                           -1, @stmt, nil);
  writeln('prepare=', rc);

  while sqlite3_step(stmt) = SQLITE_ROW do
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
end;

begin
  writeln('--- File Database ---');
  { per-binary DB path — see test_sqlite_crud.pas: a shared /tmp file races across the
    concurrent -O0/-O2/-O3 optdiff runs and reports a bogus optimization diff. }
  RunTest(ParamStr(0) + '.db');
  writeln('--- In-Memory Database ---');
  RunTest(':memory:');
end.
