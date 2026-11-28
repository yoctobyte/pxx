/* SPDX-License-Identifier: Zlib */
/* guarded ONLY by #pragma once (feature-c-pragma-once): a second splice
   reaches the #error. test/c_xkb_preproc.c includes it by three spellings. */
#pragma once
#ifdef ONCE_H_SPLICED
#error once.h was spliced twice: #pragma once is not honoured
#endif
#define ONCE_H_SPLICED 1
static int once_value(void) { return 41; }
