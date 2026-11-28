/* gcc-built driver for c_freestanding_sse_float_on_request.c (a pxx
   --freestanding -msse2 object). */
#include <stdio.h>
double scale(double x, int n);
double vsum(int n, ...);
float half(float f);
int main(void) {
  printf("%.6f %.3f %.3f\n", scale(2.0, 5), vsum(3, 1.5, 2.25, -0.5), (double)half(7.0f));
  return 0;
}
