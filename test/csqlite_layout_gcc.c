#include <stdio.h>
#include <stdlib.h>
#include <stddef.h>

#define SQLITE_THREADSAFE 0
#define SQLITE_OMIT_LOAD_EXTENSION 1
#include "sqlite3.h"

// Re-declare internal structs we want to inspect if they aren't in sqlite3.h
// Wait, sqlite3.h defines sqlite3_io_methods, sqlite3_file, etc.
#define OFF(T, F) ((unsigned long)offsetof(T, F))

int main(void) {
  printf("sizeof sqlite3_io_methods=%lu\n", (unsigned long)sizeof(struct sqlite3_io_methods));
  printf("offset xClose=%lu\n", OFF(struct sqlite3_io_methods, xClose));
  printf("offset xRead=%lu\n", OFF(struct sqlite3_io_methods, xRead));
  printf("offset xWrite=%lu\n", OFF(struct sqlite3_io_methods, xWrite));
  printf("offset xTruncate=%lu\n", OFF(struct sqlite3_io_methods, xTruncate));
  printf("offset xSync=%lu\n", OFF(struct sqlite3_io_methods, xSync));
  printf("offset xFileSize=%lu\n", OFF(struct sqlite3_io_methods, xFileSize));
  return 0;
}
