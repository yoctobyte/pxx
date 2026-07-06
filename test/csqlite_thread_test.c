/*
 * Multithreaded SQLite over the libc-free PXX pthread shim (lib/crtl pthread.h/.c
 * bridged to the PAL via lib/rtl/palpthread.pas). Exercises both supported
 * threading models:
 *   1. shared connection, SQLITE_OPEN_FULLMUTEX (serialized) — N threads hammer
 *      ONE connection concurrently; sqlite's per-connection recursive mutex (our
 *      pthread_mutex) must serialize them.
 *   2. per-thread connections (multithread) — N threads each own a :memory: db;
 *      concurrent heap + sqlite global init must stay coherent.
 *
 * Build (x86-64, --threadsafe): the pthread create/join path lowers onto
 * __pxxclone, which requires the thread-safe runtime.
 *   pascal26 --threadsafe -Ilib/crtl/include -Ilib/crtl/src \
 *            -Ilibrary_candidates/sqlite test/csqlite_thread_test.c /tmp/x && /tmp/x
 *
 * Deterministic output: "shared OK\nperthread OK\nall OK".
 */
#ifdef USE_SYSTEM_SQLITE
#include <stdio.h>
#include <pthread.h>
#include <sqlite3.h>
#else
#define SQLITE_THREADSAFE 1
#define SQLITE_HOMEGROWN_RECURSIVE_MUTEX 1
#define SQLITE_OMIT_LOAD_EXTENSION 1
#include "ctype.c"
#include "string.c"
#include "stdlib.c"
#include "stdio.c"
#include "math.c"
#include "locale.c"
#include "sqlite3.c"
#include <pthread.h>
#endif

#define NTHREAD 8
#define NROW    1000

/* ---- model 1: shared serialized connection ---- */

static sqlite3 *g_shared;

static void *shared_worker(void *arg) {
  long id = (long)arg;
  int i;
  for (i = 0; i < NROW; i++) {
    sqlite3_stmt *st;
    sqlite3_prepare_v2(g_shared, "INSERT INTO t(tid,seq) VALUES(?,?)", -1, &st, 0);
    sqlite3_bind_int(st, 1, (int)id);
    sqlite3_bind_int(st, 2, i);
    sqlite3_step(st);
    sqlite3_finalize(st);
  }
  return 0;
}

static int run_shared(void) {
  pthread_t th[NTHREAD];
  long i;
  long cnt, stid, sseq, want_stid = 0, want_sseq = 0, k;
  sqlite3_stmt *st;

  if (sqlite3_open_v2(":memory:", &g_shared,
                      SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
                      0) != SQLITE_OK)
    return 0;
  sqlite3_exec(g_shared, "CREATE TABLE t(tid INTEGER, seq INTEGER)", 0, 0, 0);

  for (i = 0; i < NTHREAD; i++) pthread_create(&th[i], 0, shared_worker, (void *)i);
  for (i = 0; i < NTHREAD; i++) pthread_join(th[i], 0);

  sqlite3_prepare_v2(g_shared, "SELECT COUNT(*), SUM(tid), SUM(seq) FROM t", -1, &st, 0);
  sqlite3_step(st);
  cnt = sqlite3_column_int(st, 0);
  stid = sqlite3_column_int(st, 1);
  sseq = sqlite3_column_int(st, 2);
  sqlite3_finalize(st);
  sqlite3_close(g_shared);

  for (k = 0; k < NTHREAD; k++) want_stid += k * NROW;   /* each tid appears NROW times */
  for (k = 0; k < NROW; k++)    want_sseq += k * NTHREAD; /* each seq appears NTHREAD times */
  return cnt == (long)NTHREAD * NROW && stid == want_stid && sseq == want_sseq;
}

/* ---- model 2: per-thread independent connections ---- */

static int g_perthread_ok[NTHREAD];

static void *own_worker(void *arg) {
  long id = (long)arg;
  sqlite3 *db;
  int i, c = 0;
  sqlite3_stmt *st;
  if (sqlite3_open(":memory:", &db) == SQLITE_OK) {
    sqlite3_exec(db, "CREATE TABLE t(v INTEGER)", 0, 0, 0);
    for (i = 0; i < NROW; i++) {
      sqlite3_prepare_v2(db, "INSERT INTO t(v) VALUES(?)", -1, &st, 0);
      sqlite3_bind_int(st, 1, i);
      sqlite3_step(st);
      sqlite3_finalize(st);
    }
    sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM t", -1, &st, 0);
    sqlite3_step(st);
    c = sqlite3_column_int(st, 0);
    sqlite3_finalize(st);
    sqlite3_close(db);
  }
  g_perthread_ok[id] = (c == NROW);
  return 0;
}

static int run_perthread(void) {
  pthread_t th[NTHREAD];
  long i;
  int ok = 1;
  for (i = 0; i < NTHREAD; i++) pthread_create(&th[i], 0, own_worker, (void *)i);
  for (i = 0; i < NTHREAD; i++) pthread_join(th[i], 0);
  for (i = 0; i < NTHREAD; i++) if (!g_perthread_ok[i]) ok = 0;
  return ok;
}

int main(void) {
  int a = run_shared();
  int b = run_perthread();
  printf("shared %s\n", a ? "OK" : "FAIL");
  printf("perthread %s\n", b ? "OK" : "FAIL");
  printf("all %s\n", (a && b) ? "OK" : "FAIL");
  return (a && b) ? 0 : 1;
}
