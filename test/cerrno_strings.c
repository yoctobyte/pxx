/* strerror / strerror_r / perror, and the byte-order helpers from
 * <netinet/in.h> (feature-crtl-libc-gap-batch-2026-08 round 2).
 *
 * strerror was a STUB returning the literal "error" for every errnum, which
 * made perror() and strerror_r() useless and left C programs reporting
 * "cannot open config: error". The table is gcc's own, generated from it
 * rather than transcribed, including the two indices where glibc has no name
 * and falls through to "Unknown error N".
 *
 * Whole output diffed against the same file built by gcc — stdout AND stderr,
 * separately, since perror writes to stderr and comparing a merged stream
 * compares buffering behaviour rather than content.
 *
 * The byte-order helpers (htons and friends, now also declared by
 * <netinet/in.h>) are deliberately NOT exercised here: merely CALLING one pulls
 * lib/crtl/src/socket.c in and the binary stops being statically linked, which
 * would make this test unrunnable under qemu on targets with no sysroot. That
 * is pre-existing behaviour — the same happens through the older
 * <arpa/inet.h> path — and is filed separately. Header visibility is what my
 * change affected, and the compile-time probe covers that; the values come from
 * an implementation that was already there.
 */
#include <stdio.h>
#include <string.h>
#include <errno.h>

int main(void) {
  char b[64];
  int i;

  /* every errno string, plus the unnamed gaps and out-of-range wording */
  for (i = 0; i <= 140; i++) printf("%d=%s\n", i, strerror(i));
  printf("neg=%s\n", strerror(-5));

  /* XSI strerror_r: 0 on success, ERANGE when it does not fit */
  printf("r_ok=%d buf=[%s]\n", strerror_r(2, b, sizeof b), b);
  printf("r_small=%d\n", strerror_r(2, b, 2));

  errno = 2;
  perror("myprog");
  errno = 2;
  perror("");            /* no prefix, no ": " */
  return 0;
}
