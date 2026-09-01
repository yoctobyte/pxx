/* SPDX-License-Identifier: Zlib */
/*
 * The C frontend announces GNU C 2.7, and the reason is layout.
 *
 * ROW 2 IS THE WHOLE TEST. Real C guards __attribute__ behind __GNUC__ and
 * defines it away when the macro is absent:
 *
 *     #if !__GNUC_PREREQ(2,7)
 *     # ifndef __attribute__
 *     #  define __attribute__(x)
 *     # endif
 *     #endif
 *
 * That is busybox's include/platform.h verbatim, and it is the shape every
 * portable C header uses. Without __GNUC__ the guard fires, PACKED expands to
 * nothing, and a packed struct silently gains padding -- 12 bytes where gcc
 * makes 8, with every field after the first read from the wrong offset. No
 * diagnostic; just wrong values. Row 2 reproduces the guard rather than
 * describing it, so the row fails if the announcement is ever withdrawn.
 *
 * Row 1 pins the version. It is a CAPABILITY CLAIM: 2.7 is the lowest that
 * unlocks __attribute__, and every higher number turns on builtins this
 * frontend does not have (typeof, __builtin_unreachable, __builtin_constant_p,
 * inline asm). Raising it is a decision about what pxx implements, not a
 * cosmetic bump, so it is asserted.
 *
 * Row 3 is the negative control: WITH the guard in place, the same struct
 * WITHOUT the attribute still pads. If row 3 ever printed 8, row 2 would be
 * passing for free -- it would be measuring a target that packs by accident.
 *
 * Rows 5-6 are the 2.7-era extensions that come with the claim and that this
 * frontend really does implement.
 *
 * ROW 1 IS THE ONE ROW THAT IS NOT A GCC DIFF. Compiled by a real gcc it
 * prints `1 1 1'; here it must print `1 0 0', because the claim is 2.7 exactly
 * and 2.8 and 4.5 must stay false. Rows 2-6 do match gcc, and were checked
 * against it.
 *
 * feature-c-corpus-busybox-multi-applet
 */
#include <stdio.h>
#include <stdint.h>

/* busybox include/platform.h, the relevant six lines, copied not paraphrased. */
#undef __GNUC_PREREQ
#if defined __GNUC__ && defined __GNUC_MINOR__
# define __GNUC_PREREQ(maj, min) \
                ((__GNUC__ << 16) + __GNUC_MINOR__ >= ((maj) << 16) + (min))
#else
# define __GNUC_PREREQ(maj, min) 0
#endif

#if !__GNUC_PREREQ(2,7)
# ifndef __attribute__
#  define __attribute__(x)
# endif
#endif

#define PACKED __attribute__ ((__packed__))

struct payload {
  uint8_t  method;
  uint8_t  flags;
  uint32_t mtime;
  uint8_t  xtra;
  uint8_t  os;
} PACKED;

struct unpacked {
  uint8_t  method;
  uint8_t  flags;
  uint32_t mtime;
  uint8_t  xtra;
  uint8_t  os;
};

static __inline__ int twice(int x) { return x + x; }

int main(void) {
  struct payload p;
  printf("1 %d %d %d\n", __GNUC_PREREQ(2,7), __GNUC_PREREQ(2,8), __GNUC_PREREQ(4,5));
  printf("2 %d\n", (int)sizeof(struct payload));
  printf("3 %d\n", (int)sizeof(struct unpacked));
  /* Field offsets, which is what the padding actually costs. */
  printf("4 %d %d %d\n",
         (int)((char *)&p.mtime - (char *)&p),
         (int)((char *)&p.xtra  - (char *)&p),
         (int)((char *)&p.os    - (char *)&p));
  printf("5 %d\n", twice(21));
  printf("6 %d\n", ({ int t = 20; t + 2; }));
  return 0;
}
