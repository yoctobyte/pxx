/* SPDX-License-Identifier: Zlib */
#ifndef PXX_CRTL_STDBOOL_H
#define PXX_CRTL_STDBOOL_H 1

/* bool is _Bool, as in C99 7.16 and glibc's (gcc's) header. It was `int`,
   which made `(bool)(x & 0x80)` 128 instead of 1 -- so micropython's
   `(bool)(most_sig & 0x80) == (bool)z->neg` was false for every negative
   big integer whose to_bytes filled the buffer exactly -- and made sizeof(bool)
   4 where gcc has 1, so a struct holding a bool laid out differently
   from a gcc-built object's.
   bug-crtl-stdbool-defines-bool-as-int */
/* C23 (7.18): bool, true and false are keywords, and <stdbool.h> defines
   only __bool_true_false_are_defined. A `#define true 1` there would make
   true an int again (sizeof 4, _Generic int). feature-c-std-c23 */
#if !defined(__STDC_VERSION__) || __STDC_VERSION__ < 202311L
#define bool _Bool
#define true 1
#define false 0
#endif
#define __bool_true_false_are_defined 1

#endif
