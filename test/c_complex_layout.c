/* C99 _Complex as LAYOUT (feature-c-complex-types-as-layout): sizeof,
   alignment and member offsets as gcc, both word orders and gcc's
   __complex__, and values passed and returned by value across calls (the SysV
   ABI passes _Complex float/double as one/two SSE eightbytes, the same as a
   struct of two). Values are built with memcpy, because arithmetic is not
   modelled. libffi's src/types.c is the user: ffi_type_complex_* records
   sizeof and the offset of a _Complex member. */
#include <stdio.h>
#include <stddef.h>
#include <string.h>

struct align_cf { char c; _Complex float x; };
struct align_cd { char c; double _Complex x; };
struct pair { int tag; __complex__ double z; float tail; };

static _Complex double swap_d(_Complex double z) {
  double p[2], q[2];
  memcpy(p, &z, sizeof p);
  q[0] = p[1]; q[1] = p[0];
  memcpy(&z, q, sizeof q);
  return z;
}

static _Complex float scale_f(_Complex float z, int k) {
  float p[2];
  memcpy(p, &z, sizeof p);
  p[0] *= (float)k; p[1] *= (float)k;
  memcpy(&z, p, sizeof p);
  return z;
}

int main(void) {
  printf("sizeof cf %d cd %d\n", (int)sizeof(_Complex float), (int)sizeof(_Complex double));
  printf("align cf %d cd %d\n", (int)offsetof(struct align_cf, x), (int)offsetof(struct align_cd, x));
  printf("pair %d z@%d tail@%d\n", (int)sizeof(struct pair), (int)offsetof(struct pair, z),
         (int)offsetof(struct pair, tail));

  double in[2] = { 1.5, -2.25 };
  _Complex double z;
  memcpy(&z, in, sizeof in);
  _Complex double w = swap_d(z);
  double out[2];
  memcpy(out, &w, sizeof out);
  printf("swap %g %g\n", out[0], out[1]);

  float fin[2] = { 3.0f, 0.5f };
  _Complex float f;
  memcpy(&f, fin, sizeof fin);
  f = scale_f(f, 4);
  float fout[2];
  memcpy(fout, &f, sizeof fout);
  printf("scale %g %g\n", fout[0], fout[1]);

  struct pair pr = { 7, 0, 1.0f };
  pr.z = w;
  struct pair copy = pr;
  memcpy(out, &copy.z, sizeof out);
  printf("copy %d %g %g %g\n", copy.tag, out[0], out[1], copy.tail);
  _Complex double arr[3];
  printf("array %d\n", (int)sizeof arr);

  /* a complex type is a scalar to an initialiser: one value each, real part */
  _Complex double ca[3] = { 1.0, 2.0 };
  double cv[6];
  memcpy(cv, ca, sizeof cv);
  printf("init array %g %g %g %g %g %g\n", cv[0], cv[1], cv[2], cv[3], cv[4], cv[5]);
  static struct pair sp = { 3, 4.5, 6.0f };
  memcpy(out, &sp.z, sizeof out);
  printf("init static %d %g %g %g\n", sp.tag, out[0], out[1], sp.tail);
  return 0;
}
