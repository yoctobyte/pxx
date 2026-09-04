/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <glob.h> -- POSIX pathname expansion.
 *
 * Flag VALUES are glibc's, read off the host header rather than chosen, for
 * the reason <fnmatch.h> gives: callers write them as a bitmask and a
 * differently-numbered set turns into the wrong behaviour rather than a
 * compile error.
 *
 * THREE GNU EXTENSIONS ARE DELIBERATELY NOT DEFINED -- GLOB_BRACE,
 * GLOB_TILDE / GLOB_TILDE_CHECK and GLOB_ALTDIRFUNC. Each would be a silent
 * wrong answer if defined and ignored: GLOB_BRACE ignored means `{a,b}' is
 * matched as a literal filename and the caller's expansion silently
 * disappears, and GLOB_ALTDIRFUNC ignored means the caller's own directory
 * hooks are bypassed and the REAL filesystem is read instead. A caller that
 * tests `#ifdef GLOB_BRACE' gets the right answer -- absent -- and one that
 * writes the flag unconditionally gets a compile error naming the flag,
 * which is the diagnostic you want. Same rule as FNM_EXTMATCH in <fnmatch.h>.
 * busybox's hush.c reaches the same conclusion in its own words at
 * shell/hush.c:3293: "There is a GNU extension, GLOB_BRACE, but it is not
 * usable" -- and does its brace expansion itself.
 *
 * GLOB_ONLYDIR IS A HINT AND IS TREATED AS ONE. POSIX and glibc both allow an
 * implementation to ignore it, and glibc's own manual says non-directories
 * "may" still appear; a caller that relies on it filtering is already broken
 * against glibc. It is defined so such a caller compiles and gets glibc's
 * behaviour, not a different one.
 *
 * Found attempting busybox on i386: shell/hush.c stops at this include.
 * bug-b-crtl-host-header-fallback-leaks-BEGIN-DECLS
 */
#ifndef _CRTL_GLOB_H
#define _CRTL_GLOB_H

#include <stddef.h>

/* Flags to glob(). */
#define GLOB_ERR      (1 << 0)   /* stop on an unreadable directory        */
#define GLOB_MARK     (1 << 1)   /* append '/' to a directory              */
#define GLOB_NOSORT   (1 << 2)   /* do not sort the result                 */
#define GLOB_DOOFFS   (1 << 3)   /* reserve gl_offs leading NULL slots     */
#define GLOB_NOCHECK  (1 << 4)   /* on no match, return the pattern itself */
#define GLOB_APPEND   (1 << 5)   /* append to a previous glob()'s result   */
#define GLOB_NOESCAPE (1 << 6)   /* backslash is an ordinary character     */
#define GLOB_PERIOD   (1 << 7)   /* a leading '.' may be matched by a
                                    wildcard (the GNU relaxation)          */
#define GLOB_MAGCHAR  (1 << 8)   /* SET BY glob() in gl_flags, never
                                    passed in: the pattern had a wildcard  */
#define GLOB_NOMAGIC  (1 << 11)  /* like NOCHECK, but only when the
                                    pattern had no wildcard at all         */
#define GLOB_ONLYDIR  (1 << 13)  /* hint only -- see the note above        */

/* Return values. Note GLOB_NOMATCH is 3, not 1: the three error codes are not
   a contiguous run and a caller testing `if (gr)' then branching on the value
   is the normal shape. */
#define GLOB_NOSPACE 1           /* out of memory                          */
#define GLOB_ABORTED 2           /* GLOB_ERR was set, or errfunc said stop */
#define GLOB_NOMATCH 3           /* nothing matched                        */
#define GLOB_NOSYS   4           /* not implemented (never returned here)  */

#define GLOB_ABEND GLOB_ABORTED  /* the older spelling                     */

typedef struct {
  size_t  gl_pathc;   /* how many paths matched, NOT counting gl_offs     */
  char  **gl_pathv;   /* gl_offs NULLs, then gl_pathc paths, then a NULL  */
  size_t  gl_offs;    /* leading slots to reserve, honoured on GLOB_DOOFFS */
  int     gl_flags;   /* the flags passed in, plus GLOB_MAGCHAR           */
} glob_t;

/* GLOB_APPEND MEANS THE CALLER OWNS THE ACCUMULATION, and it is the one flag
   that reads a field of *pglob rather than only writing one: gl_pathc and
   gl_pathv must be the ones a previous glob() left. Passing it to a glob_t
   that was never filled reads uninitialised memory -- glibc has the same
   contract. */
int  glob(const char *pattern, int flags,
          int (*errfunc)(const char *epath, int eerrno), glob_t *pglob);
void globfree(glob_t *pglob);

/* Does this pattern contain anything glob() would expand? `quote' non-zero
   means a backslash escapes. GNU, and busybox-adjacent code asks for it. */
int  glob_pattern_p(const char *pattern, int quote);

#endif /* _CRTL_GLOB_H */
