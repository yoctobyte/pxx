/* setvbuf reports what the unbuffered crtl can actually do: _IONBF succeeds,
   _IOFBF/_IOLBF fail (nonzero), an invalid mode fails. It used to return 0 for
   everything. The expected values are crtl's, NOT gcc's: glibc buffers, so it
   answers 0 to all three valid modes. That divergence is the honest one.
   feature-c-crtl-stdio-buffering-and-setvbuf */
#include <stdio.h>
int main(void) {
  static char buf[64];
  printf("IONBF %d\n", setvbuf(stdout, NULL, _IONBF, 0) == 0);
  printf("IOFBF %d\n", setvbuf(stdout, buf, _IOFBF, sizeof buf) != 0);
  printf("IOLBF %d\n", setvbuf(stdout, NULL, _IOLBF, 0) != 0);
  printf("bad   %d\n", setvbuf(stdout, NULL, 77, 0) != 0);
  setbuf(stdout, NULL);
  printf("after %s\n", "still-writes");
  return 0;
}
