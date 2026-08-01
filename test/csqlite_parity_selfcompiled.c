/*
 * Half of the SQLite parity pair (test-sqlite-external-vs-self-compiled-parity):
 * runs the SAME deterministic CREATE TABLE / INSERT / SELECT ... ORDER BY
 * workload as test/test_sqlite_parity_external.pas, but through the
 * self-compiled `library_candidates/sqlite/sqlite3.c` amalgamation (unity
 * build over the libc-free crtl, same shape as csqlite_file_probe.c /
 * csqlite_thread_test.c) instead of the external libsqlite3.so.0 import.
 * `make test-sqlite-parity` diffs the two programs' stdout byte-for-byte.
 *
 * Build (self-compiled, libc-free):
 *   pascal26 -Ilib/crtl/include -Ilib/crtl/src -Ilibrary_candidates/sqlite \
 *            test/csqlite_parity_selfcompiled.c /tmp/x && /tmp/x
 *
 * USE_SYSTEM_SQLITE is accepted too (real headers + gcc) purely so this file
 * can double as its own oracle sanity check outside pxx; the committed gate
 * always builds the #else (self-compiled) arm through pxx.
 */
#ifdef USE_SYSTEM_SQLITE
#include <stdio.h>
#include <sqlite3.h>
#else
#define SQLITE_THREADSAFE 0
#define SQLITE_OMIT_LOAD_EXTENSION 1
#define SQLITE_MAX_MMAP_SIZE 0
#include "ctype.c"
#include "string.c"
#include "stdlib.c"
#include "stdio.c"
#include "math.c"
#include "locale.c"
#include "sqlite3.c"
#endif

static sqlite3 *db;

static void run(const char *sql) {
  int rc = sqlite3_exec(db, sql, 0, 0, 0);
  if (rc != SQLITE_OK) printf("exec failed rc=%d\n", rc);
}

int main(void) {
  int rc;
  sqlite3_stmt *stmt = 0;

  rc = sqlite3_open(":memory:", &db);
  printf("open=%d\n", rc);

  run("CREATE TABLE t(id INTEGER, name TEXT);");
  run("INSERT INTO t VALUES(1, 'alice');");
  run("INSERT INTO t VALUES(2, 'bob');");
  run("INSERT INTO t VALUES(3, 'carol');");
  run("INSERT INTO t VALUES(4, 'dave');");

  rc = sqlite3_prepare_v2(db, "SELECT id, name FROM t ORDER BY id;", -1, &stmt, 0);
  printf("prepare=%d\n", rc);

  while (sqlite3_step(stmt) == SQLITE_ROW) {
    int id = sqlite3_column_int(stmt, 0);
    const unsigned char *name = sqlite3_column_text(stmt, 1);
    printf("%d %s\n", id, name);
  }

  rc = sqlite3_finalize(stmt);
  printf("finalize=%d\n", rc);
  rc = sqlite3_close(db);
  printf("close=%d\n", rc);
  return 0;
}
