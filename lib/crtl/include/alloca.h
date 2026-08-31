/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <alloca.h>.
 *
 * There is no alloca FUNCTION here and there must not be: alloca allocates in
 * the CALLER's frame, so a real call would allocate in its own and hand back a
 * pointer into a frame that is already gone. The compiler lowers it directly
 * (cparser.inc -> AN_ALLOCA -> IR_ALLOCA).
 *
 * glibc's header carries a declaration AND this macro, and the macro is what
 * every compilation actually uses. Carrying only the macro is the same result
 * with one fewer way to go wrong -- without it, the declaration wins, pxx's
 * builtin path steps aside for what looks like a user definition (the FindProc
 * guard), and the program links against a symbol that does not exist.
 */
#ifndef _CRTL_ALLOCA_H
#define _CRTL_ALLOCA_H

#include <stddef.h>

#define alloca(size) __builtin_alloca(size)

#endif
