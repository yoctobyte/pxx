/* `sizeof(*s.fp)` where `fp` is a struct member of type `int (*)[4]`.

   The struct builder's parenthesised-declarator arm was written for FUNCTION
   pointers, whose pointee has no type, so it hardcoded the field's pointee to
   tyUnknown. `int (*fp)[4]` reaches the same arm -- ParseCDeclType parks its
   name in CTypeFnPtrName either way -- and so recorded no pointee at all. The
   field side also had no extent column (UFldPtrElemArrLen is new here; the
   symbol side has had SymPtrElemArrLen all along), so even a recorded pointee
   could only have answered the ELEMENT size.

   THE int SPELLING CANNOT DETECT EITHER FAULT. The tyUnknown default is 4,
   which is exactly sizeof(int), so `sizeof(*s.ip)` read like a plausible
   "element size" answer while the field held nothing whatsoever. The `dp` and
   `cp` rows are the ones that separate a real answer from a default, and they
   are why this test does not consist of int rows: a suite of int rows here is
   a guard that cannot fail.

   Every size is checked against the MEASURED stride of the pointer it belongs
   to, never a spelled-out constant. `plain`/`dplain` are the controls for a
   non-array pointee, and the indexing rows are the control for the addressing
   path, which was correct throughout -- the field could always be dereferenced
   and subscripted, it just could not be sized. */
#include <stdio.h>

struct S {
  int    (*ip)[4];
  double (*dp)[4];
  char   (*cp)[7];
  int    (*ip2)[2][3];
  int     *plain;
  double  *dplain;
};

int main(void) {
  int a4[4]; double d4[4]; char c7[7]; int a23[2][3];
  struct S s;
  int fails = 0;
  s.ip = &a4; s.dp = &d4; s.cp = &c7; s.ip2 = &a23;
  s.plain = a4; s.dplain = d4;

#define CHK(f, expr) do {                                                     \
    long stride = (char *)((expr) + 1) - (char *)(expr);                      \
    if ((long)sizeof(*(expr)) != stride) {                                    \
      printf("FAIL %s size %ld vs stride %ld\n",                              \
             f, (long)sizeof(*(expr)), stride); fails++; }                    \
  } while (0)

  CHK("ip",     s.ip);
  CHK("dp",     s.dp);
  CHK("cp",     s.cp);
  CHK("ip2",    s.ip2);
  CHK("plain",  s.plain);
  CHK("dplain", s.dplain);

  /* the pointee is the whole object pointed at, not one element of it */
  if (sizeof(*s.ip)  != sizeof(a4))  { printf("FAIL ip vs a4\n");   fails++; }
  if (sizeof(*s.dp)  != sizeof(d4))  { printf("FAIL dp vs d4\n");   fails++; }
  if (sizeof(*s.cp)  != sizeof(c7))  { printf("FAIL cp vs c7\n");   fails++; }
  if (sizeof(*s.ip2) != sizeof(a23)) { printf("FAIL ip2 vs a23\n"); fails++; }

  /* the four pointees must not all collapse to one default */
  if (sizeof(*s.ip) == sizeof(*s.dp)) { printf("FAIL int and double pointees agree\n"); fails++; }
  if (sizeof(*s.cp) == sizeof(*s.ip)) { printf("FAIL char and int pointees agree\n");   fails++; }

  /* control: addressing through the field, correct before this fix */
  (*s.ip)[1] = 77;
  if (a4[1] != 77) { printf("FAIL (*s.ip)[1] = %d\n", a4[1]); fails++; }

  if (fails == 0)
    printf("FIELD PTRARR OK %zu %zu %zu %zu\n",
           sizeof(*s.ip), sizeof(*s.dp), sizeof(*s.cp), sizeof(*s.ip2));
  return fails;
}
