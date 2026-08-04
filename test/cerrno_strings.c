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
 * The byte-order helpers ARE exercised here as of 2026-08-05. They were left
 * out because calling one used to pull in an implementation the compiler then
 * could not see, so the call fell back to a glibc import and the binary stopped
 * being statically linked — which made this test unrunnable under qemu on a
 * target with no sysroot. That was
 * bug-cfront-spurious-dt-needed-libc-with-no-imports, now fixed: the impl moved
 * to src/netinet/in.c, where the auto-pull convention actually reaches it.
 *
 * So their presence here is the end-to-end proof of that fix. If this file ever
 * goes back to being dynamically linked, these are the lines that will say so —
 * on every cross target, where the missing sysroot turns it into a hard failure
 * rather than a silent dependency.
 */
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <netinet/in.h>

int main(void) {
  char b[64];
  int i;

  /* every errno string, plus the unnamed gaps and out-of-range wording */
  for (i = 0; i <= 140; i++) printf("%d=%s\n", i, strerror(i));
  printf("neg=%s\n", strerror(-5));

  /* XSI strerror_r: 0 on success, ERANGE when it does not fit */
  printf("r_ok=%d buf=[%s]\n", strerror_r(2, b, sizeof b), b);
  printf("r_small=%d\n", strerror_r(2, b, 2));

  /* byte order: values against gcc, and the swap must be a real swap on a
     little-endian host rather than an accidental identity */
  printf("htons=%u ntohs=%u\n", (unsigned)htons(0x1234), (unsigned)ntohs(0x1234));
  printf("htonl=%u ntohl=%u\n", (unsigned)htonl(0x12345678u), (unsigned)ntohl(0x12345678u));
  printf("roundtrip=%d %d\n", ntohs(htons(0xBEEF)) == 0xBEEF,
                               ntohl(htonl(0xDEADBEEFu)) == 0xDEADBEEFu);

  errno = 2;
  perror("myprog");
  errno = 2;
  perror("");            /* no prefix, no ": " */
  return 0;
}
