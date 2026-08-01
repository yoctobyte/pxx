{ Half of the SQLite parity pair (test-sqlite-external-vs-self-compiled-parity):
  runs a small deterministic CREATE TABLE / INSERT / SELECT ... ORDER BY
  workload through the EXTERNAL `libsqlite3.so.0` import path (`uses sqlite3`,
  the same binding test_sqlite_crud.pas/test_sqlite_crud_autotyped.pas use).
  The other half, test/csqlite_parity_selfcompiled.c, runs the identical SQL
  through the self-compiled `library_candidates/sqlite/sqlite3.c` amalgamation.
  `make test-sqlite-parity` diffs their stdout byte-for-byte — the two SQLite
  builds must agree exactly on this workload. Always an in-memory database, so
  there is no on-disk state and no /tmp race between the two runs. }
program test_sqlite_parity_external;
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

procedure Exec(const sql: string);
var
  exec_rc: auto;
begin
  exec_rc := sqlite3_exec(db, sql, nil, nil, nil);
  if exec_rc <> SQLITE_OK then writeln('exec failed rc=', exec_rc);
end;

begin
  Init;

  rc := sqlite3_open(':memory:', @db);
  writeln('open=', rc);

  Exec('CREATE TABLE t(id INTEGER, name TEXT);');
  Exec('INSERT INTO t VALUES(1, ''alice'');');
  Exec('INSERT INTO t VALUES(2, ''bob'');');
  Exec('INSERT INTO t VALUES(3, ''carol'');');
  Exec('INSERT INTO t VALUES(4, ''dave'');');

  rc := sqlite3_prepare_v2(db, 'SELECT id, name FROM t ORDER BY id;',
                           -1, @stmt, nil);
  writeln('prepare=', rc);

  while sqlite3_step(stmt) = SQLITE_ROW do
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
