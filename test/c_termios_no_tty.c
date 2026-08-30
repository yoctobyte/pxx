/* crtl's termios. Everything here is exercisable WITHOUT a terminal, because
   under the test harness fd 0 is a pipe or a file and never a tty -- so the
   rows are the pure-computation helpers plus the error path, and each was
   taken from a glibc-built binary of this same file.

   What is deliberately NOT asserted: sizeof(struct termios). crtl uses the
   KERNEL layout (NCCS 19, no c_ispeed/c_ospeed) because that is what TCGETS
   actually reads and writes, so the ioctl needs no translation; glibc's
   userspace struct is 60 bytes and translates. Comparing the two sizes would
   assert a difference we chose on purpose. The c_cc SUBSCRIPTS are the same in
   both, which is why the VMIN/VTIME rows below are a real comparison.

   TWO ROWS HERE DISAGREE WITH glibc ON PURPOSE, and they are the ones to read
   before changing anything: `ispeed follows ospeed` and the B115200 row. crtl
   keeps the line speed where the KERNEL keeps it, in the CBAUD bits of
   c_cflag, so there is one speed and both directions see it. Modern glibc was
   MEASURED rather than assumed, and it does something else: separate
   c_ispeed/c_ospeed fields, cfgetospeed returning the numeric rate (9600, not
   B9600 == 0o15), and cfsetispeed(B115200) writing a termios2 BOTHER encoding
   into the high c_cflag bits while leaving the output speed alone.

   Reproducing that means carrying termios2. We do not, on the compat ceiling:
   real code sets both directions to the same Bxxx and reads it back, which
   works here exactly. Split input/output rates and non-standard baud rates are
   unsupported and the header says so. Everything else in this file — cfmakeraw
   bit-for-bit, the ENOTTY path, the c_cc subscripts — DOES match a glibc-built
   binary of this same file, which is what makes those rows a comparison rather
   than two self-consistent answers.
   feature-c-corpus-busybox-applet */
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <termios.h>
#include <unistd.h>

int main(void)
{
  struct termios t;
  int rc;

  /* cfmakeraw against a fully-set struct: the assertion is the exact SET of
     bits it clears and sets, not merely that it cleared something. */
  memset(&t, 0, sizeof t);
  t.c_iflag = ICRNL | IXON | ISTRIP | BRKINT | IGNBRK | INLCR | IGNCR | PARMRK;
  t.c_oflag = OPOST | ONLCR;
  t.c_cflag = CS7 | PARENB | CREAD | CLOCAL;
  t.c_lflag = ECHO | ECHOE | ICANON | ISIG | IEXTEN | ECHONL | TOSTOP;
  cfmakeraw(&t);
  printf("raw iflag: %lu\n", (unsigned long)t.c_iflag);
  printf("raw oflag: %lu\n", (unsigned long)t.c_oflag);
  printf("raw lflag: %lu\n", (unsigned long)t.c_lflag);
  printf("raw cs8: %d parenb: %d cread kept: %d clocal kept: %d\n",
         (t.c_cflag & CSIZE) == CS8, (t.c_cflag & PARENB) != 0,
         (t.c_cflag & CREAD) != 0, (t.c_cflag & CLOCAL) != 0);
  printf("raw vmin: %d vtime: %d\n", t.c_cc[VMIN], t.c_cc[VTIME]);

  /* speed: one field, read two ways */
  memset(&t, 0, sizeof t);
  t.c_cflag = CS8 | CREAD;
  printf("setospeed: %d\n", cfsetospeed(&t, B9600));
  printf("getospeed==B9600: %d\n", cfgetospeed(&t) == B9600);
  printf("ispeed follows ospeed: %d\n", cfgetispeed(&t) == B9600);   /* glibc: 0 */
  printf("cs8 survived: %d\n", (t.c_cflag & CSIZE) == CS8);
  printf("setispeed: %d\n", cfsetispeed(&t, B115200));
  printf("getospeed==B115200: %d\n", cfgetospeed(&t) == B115200);    /* glibc: 0 */

  /* the error path: not a tty, and the errno says so rather than 0 */
  errno = 0;
  rc = tcgetattr(0, &t);
  printf("tcgetattr(pipe): %d ENOTTY: %d\n", rc, errno == ENOTTY);

  /* c_cc subscripts agree with glibc's, which is what makes the rows above a
     comparison rather than two self-consistent answers */
  printf("VMIN=%d VTIME=%d VINTR=%d VEOF=%d\n", VMIN, VTIME, VINTR, VEOF);
  return 0;
}
