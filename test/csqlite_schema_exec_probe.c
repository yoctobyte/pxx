#define SQLITE_THREADSAFE 0
#define SQLITE_OMIT_LOAD_EXTENSION 1

#include "ctype.c"
#include "string.c"
#include "stdlib.c"
#include "stdio.c"
#include "math.c"
#include "locale.c"
#include "sqlite3.c"

int main(void) {
  sqlite3 *db = 0;
  char *errmsg = 0;
  int rc;

  rc = sqlite3_open(":memory:", &db);
  printf("open=%d\n", rc);
  if (rc != SQLITE_OK) {
    if (db) printf("open-msg=%s\n", sqlite3_errmsg(db));
    return 1;
  }

  rc = sqlite3_exec(db, "CREATE TABLE t(id INTEGER, name TEXT);", 0, 0, &errmsg);
  printf("exec=%d\n", rc);
  if (rc != SQLITE_OK) {
    printf("exec-msg=%s\n", errmsg ? errmsg : sqlite3_errmsg(db));
  }

  printf("close=%d\n", sqlite3_close(db));
  return rc == SQLITE_OK ? 0 : 2;
}
