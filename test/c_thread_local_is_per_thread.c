/* `__thread` gives one copy per thread — the half a single-threaded run
   physically cannot observe.
   bug-c-__thread-is-accepted-and-silently-ignored-so-thread-local-storage-is-shared

   THE POSITIVE CONTROL IS THE PLAIN GLOBAL, drawn from the population the
   question is about. Every thread hammers `shared` and `mine` in the same loop
   with the same shape of write. If `mine` were an ordinary global — which is
   exactly what this compiler produced before the fix — both would show
   cross-talk; if the harness were inert, neither would. Only a real per-thread
   `mine` makes the two disagree.

   WHICH ROWS SURVIVE SERIAL EXECUTION IS THE PART WORTH KNOWING, and it is
   inherited from the Pascal twin (test_a_threadvar_is_per_thread.pas), which
   measured it after a load-dependent control went red on a busy box. If the
   threads do not overlap, a plain global still reads back each thread's own
   last write for the whole of that thread's run — so `kept` and `no-crosstalk`
   STOP DISCRIMINATING under `taskset -c 0` and go green on a broken program.
   What catches it on one CPU is:
     zeroed-on-entry — a child must see 0, not the previous thread's leftover
     main-copy       — main's own 7 must survive every child's writes
   Neither needs concurrency, which is why the verdict rests on all six rows and
   not on the two a reader would reach for first.

   NO EXPECTED VALUE CAN COLLIDE WITH A DEFAULT. `mine` is set to 100+idx, not
   to 0 or 1, and main holds 7 — so a row cannot pass by reading uninitialised
   memory that happens to match. `control-shared` asserts `shared != 7` rather
   than a specific number, because WHICH child wrote last is scheduling
   dependent and pinning it would plant the flake this design exists to avoid.

   NOT A GCC DIFFERENTIAL: gcc reaches per-thread storage through ELF TLS
   (.tbss, fs-relative) and pxx through its own GS block, so the two binaries
   cannot be compared instruction for instruction. The OBSERVABLE is identical
   and that is what this asserts — which is the whole claim. */
#include <pthread.h>
#include <stdio.h>

#define NT    4
#define CHURN 200000

__thread int mine;          /* the subject */
int shared;                 /* the positive control: a PLAIN global */

static int      seen[NT], zero[NT], cross[NT];
static long     tid[NT];

static void *body(void *arg) {
  int idx = (int)(long)arg;
  int k;
  tid[idx] = (long)pthread_self();
  zero[idx] = (mine == 0) ? 1 : 0;   /* asserted BEFORE the first write */
  mine = 100 + idx;
  for (k = 0; k < CHURN; k++) {
    shared = 900 + idx;
    if (mine != 100 + idx) cross[idx]++;
  }
  seen[idx] = mine;
  return 0;
}

int main(void) {
  pthread_t h[NT];
  int i, j, kept = 0, zeroed = 0, clean = 0, distinct = 0, dup;

  mine = 7;
  shared = 7;
  for (i = 0; i < NT; i++) { seen[i] = -1; zero[i] = -1; cross[i] = 0; tid[i] = -1; }

  for (i = 0; i < NT; i++)
    if (pthread_create(&h[i], 0, body, (void *)(long)i) != 0)
      printf("FAIL: could not spawn thread %d\n", i);
  for (i = 0; i < NT; i++) pthread_join(h[i], 0);

  for (i = 0; i < NT; i++) {
    if (seen[i] == 100 + i) kept++;
    if (zero[i] == 1)       zeroed++;
    if (cross[i] == 0)      clean++;
    dup = 0;
    for (j = 0; j < i; j++) if (tid[j] == tid[i]) dup = 1;
    if (tid[i] > 0 && !dup) distinct++;
  }

  printf("kept=%d/%d\n", kept, NT);
  printf("zeroed-on-entry=%d/%d\n", zeroed, NT);
  printf("no-crosstalk=%d/%d\n", clean, NT);
  printf("distinct-tids=%d/%d\n", distinct, NT);
  printf("control-shared=%d\n", shared != 7);
  printf("main-copy=%d\n", mine);
  if (kept == NT && zeroed == NT && clean == NT && distinct == NT
      && shared != 7 && mine == 7)
    printf("C THREAD-LOCAL OK\n");
  else
    printf("C THREAD-LOCAL FAIL\n");
  return 0;
}
