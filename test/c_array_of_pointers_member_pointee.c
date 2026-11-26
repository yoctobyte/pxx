/* An ARRAY OF POINTERS -- a struct member or a plain array -- keeps each
   element's pointee type: a store through `*s.a[i]` writes sizeof *s.a[i]
   bytes (it wrote 8 over three uint16_t neighbours), a load reads that many,
   `s.a[i][j]` indexes the pointee, and `s.a[i]++` / `a[i] + 1` step by the
   pointee (they stepped one byte). xz-utils' range encoder keeps
   `probability *probs[]` in a struct and wrote zeros (Nodisx). Expected = gcc's. */
#include <stdio.h>
#include <stdint.h>
struct one { uint16_t *a; };
struct s8 { uint8_t *a[2]; };  struct s16 { uint16_t *a[2]; }; struct s32 { uint32_t *a[2]; };
struct sd { double *a[2]; };   struct sst { struct { char c; short h; } *a[2]; };
struct s2d { uint16_t *a[2][2]; };
static void members(void) {
  { uint8_t p[8] = {1,2,3,4,5,6,7,8}; struct s8 s; s.a[0] = p; *s.a[0] = 9; printf("u8:  %u %u load=%u size=%zu\n", p[0], p[1], *s.a[0], sizeof *s.a[0]); }
  { uint16_t p[4] = {1,2,3,4}; struct s16 s; s.a[0] = p; *s.a[0] = 9; printf("u16: %u %u load=%u size=%zu\n", p[0], p[1], *s.a[0], sizeof *s.a[0]); }
  { uint32_t p[4] = {1,2,3,4}; struct s32 s; s.a[0] = p; *s.a[0] = 9; printf("u32: %u %u load=%u size=%zu\n", p[0], p[1], *s.a[0], sizeof *s.a[0]); }
  { double p[2] = {1.5, 2.5}; struct sd s; s.a[0] = p; *s.a[0] = 9.25; printf("dbl: %g %g load=%g\n", p[0], p[1], *s.a[0]); }
  { uint16_t p[4] = {1,2,3,4}; struct s16 s; s.a[1] = p + 1; s.a[1][1] = 7; printf("idx: %u %u %u %u\n", p[0], p[1], p[2], p[3]); }
  { uint16_t p[4] = {1,2,3,4}; struct s16 s; s.a[0] = p; s.a[0]++; *s.a[0] += 5; printf("inc: %u %u %u %u\n", p[0], p[1], p[2], p[3]); }
  { uint16_t p[4] = {1,2,3,4}; struct s2d s; s.a[1][0] = p; *s.a[1][0] = 9; printf("2d:  %u %u\n", p[0], p[1]); }

}
static void strides(void) {
  { uint16_t p[4] = {1,2,3,4}; struct s16 s; s.a[0] = p; s.a[0]++; printf("++ field-arr bytes: %td\n", (char *)s.a[0] - (char *)p); }
  { uint16_t p[4] = {1,2,3,4}; struct s16 s; s.a[0] = p; ++s.a[0]; printf("pre++ field-arr bytes: %td\n", (char *)s.a[0] - (char *)p); }
  { uint16_t p[4] = {1,2,3,4}; struct s16 s; s.a[0] = p; s.a[0] += 1; printf("+=1 field-arr bytes: %td\n", (char *)s.a[0] - (char *)p); }
  { uint16_t p[4] = {1,2,3,4}; struct s16 s; s.a[0] = p; s.a[0] = s.a[0] + 1; printf("=+1 field-arr bytes: %td\n", (char *)s.a[0] - (char *)p); }
  { uint16_t p[4] = {1,2,3,4}; struct one s; s.a = p; s.a++; printf("++ field bytes: %td\n", (char *)s.a - (char *)p); }
  { uint16_t p[4] = {1,2,3,4}; uint16_t *a[2]; a[0] = p; a[0]++; printf("++ ident-arr bytes: %td\n", (char *)a[0] - (char *)p); }
  { uint16_t p[4] = {1,2,3,4}; struct s16 s; s.a[0] = p; printf("s.a[0]-p elems: %td, s.a[0][1]=%u\n", (s.a[0] + 2) - p, s.a[0][1]); }

}
int main(void) { members(); strides(); return 0; }
