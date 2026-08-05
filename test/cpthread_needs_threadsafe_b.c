/* Regression: <pthread.h> without --threadsafe must fail at COMPILE time with
   the flag named, not build clean and die at load with

       symbol lookup error: undefined symbol: __pxx_pmutex_init

   __pxx_p* are pxx's own thread-PAL helpers (lib/rtl/palpthread.pas), pulled
   only under --threadsafe. Without it they stayed unbodied and were imported
   from libc.so.6, which cannot possibly supply them — an import that is a
   guess, not a dependency. The failure was at LOAD, so it survived every
   link-time check, and the message named a symbol absent from the user's
   source.

   This file is the WORKING half: with --threadsafe (which the Makefile line
   passes) it must build and run. The rejection half cannot be a compile test
   in this harness, since the harness has no "must not compile" form; it is
   recorded in the ticket with its measured before/after.
   bug-c-pthread-without-threadsafe-builds-then-dies-at-load */
#include <pthread.h>
#include <stdio.h>
static pthread_mutex_t m;
int main(void) {
  if (pthread_mutex_init(&m, 0) != 0) return 1;
  if (pthread_mutex_lock(&m) != 0)    return 2;
  if (pthread_mutex_unlock(&m) != 0)  return 3;
  return 42;
}
