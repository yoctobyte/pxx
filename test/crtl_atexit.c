/* SPDX-License-Identifier: Zlib */
/*
 * atexit(): the handlers must run on BOTH exit paths, and in LIFO order.
 *
 * The `return`-from-main path is the one this test exists for. A C program's
 * normal exit is not exit() — it is a plain return, which the compiler's entry
 * stub turns into `call main; __pxx_run_finalizers; exit_group(retval)`. That
 * runner walks unit FINALIZATION sections, so the handler list lives in Pascal
 * (lib/rtl/pxxcio.pas) and crtl's atexit() is a bridge to it. A list kept on the
 * C side would pass the exit() case here and silently skip this one — the worse
 * failure, because the program still looks fine.
 *
 * Checked here, all four gcc's own behaviour for this file:
 *   - return-from-main runs them, LIFO, and main's exit code survives the call
 *   - exit() runs them too
 *   - _Exit() does NOT (C99 7.20.4.4 is what makes it _Exit)
 *   - registration count is not capped at some round number: glibc grows
 *     without bound, so 100 handlers must all answer 0
 *
 * The other half of what this asserts is in lib-test, not here: `readelf -d`
 * must show no DT_NEEDED. atexit was DECLARED with no body, so every caller
 * bound to libc.so.6 through the unresolved-extern fallback — which on this host
 * did not even reach main ("undefined symbol: atexit"), and would have been a
 * silent loss of self-containment had it resolved.
 */
#include <stdio.h>
#include <stdlib.h>

static void h1(void) { printf("h1\n"); }
static void h2(void) { printf("h2\n"); }
static void h3(void) { printf("h3\n"); }

static void child_exit(void)  { printf("child-exit\n"); }
static void child__Exit(void) { printf("SHOULD-NOT-RUN\n"); }

int main(int argc, char **argv) {
  int i, ok = 0, bad = 0;

  /* Sub-modes, so the three exit paths are three processes and each one's
     handlers are observed by the parent's expected output. */
  if (argc > 1 && argv[1][0] == 'e') {          /* exit() drains */
    atexit(child_exit);
    printf("via-exit\n");
    fflush(stdout);
    exit(4);
  }
  if (argc > 1 && argv[1][0] == 'x') {          /* _Exit() must not */
    atexit(child__Exit);
    printf("via-_Exit\n");
    fflush(stdout);
    _Exit(5);
  }
  if (argc > 1 && argv[1][0] == 'n') {          /* no round-number cap */
    for (i = 0; i < 100; i++) { if (atexit(h1) == 0) ok++; else bad++; }
    printf("registered ok=%d bad=%d\n", ok, bad);
    fflush(stdout);
    _Exit(0);                                   /* skip the 100 printouts */
  }

  atexit(h1);
  atexit(h2);
  atexit(h3);
  printf("main-returns\n");
  return 0;                                     /* h3, h2, h1 follow this */
}
