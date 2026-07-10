#ifdef USE_SYSTEM_SQLITE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
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

static int exec_cb(void *u, int argc, char **argv, char **col) {
  (void)u; (void)col;
  printf("row:");
  for (int i = 0; i < argc; i++) printf(" %s", argv[i] ? argv[i] : "NULL");
  printf("\n");
  return 0;
}

int main(void) {
  sqlite3 *db = 0;
  char *errmsg = 0;
  int rc;
  const char *path = "/tmp/pxx_sqlite_file_probe.db";

  remove(path);
  rc = sqlite3_open(path, &db);
  printf("open rc=%d\n", rc);
  if (rc) return 1;

  rc = sqlite3_exec(db, "CREATE TABLE t(a INTEGER, b TEXT);", 0, 0, &errmsg);
  printf("create rc=%d msg=%s\n", rc, errmsg ? errmsg : "(null)");
  if (rc) return 2;

  rc = sqlite3_exec(db, "INSERT INTO t VALUES(1,'hello');", 0, 0, &errmsg);
  printf("insert rc=%d msg=%s\n", rc, errmsg ? errmsg : "(null)");
  if (rc) return 3;

  rc = sqlite3_close(db);
  printf("close rc=%d\n", rc);

  /* reopen: forces a real page read from the file */
  rc = sqlite3_open(path, &db);
  printf("reopen rc=%d\n", rc);
  rc = sqlite3_exec(db, "SELECT a,b FROM t;", exec_cb, 0, &errmsg);
  printf("select rc=%d msg=%s\n", rc, errmsg ? errmsg : "(null)");
  sqlite3_close(db);
  return 0;
}
