/* SPDX-License-Identifier: Zlib */
#ifndef PXX_CRTL_FNMATCH_H
#define PXX_CRTL_FNMATCH_H 1

/* Flag values are glibc's, read off the host header rather than chosen. They
   are part of the ABI in practice: callers write FNM_PATHNAME | FNM_PERIOD and
   a differently-numbered set turns into the wrong behaviour rather than a
   compile error. */
#define FNM_PATHNAME    (1 << 0)  /* no wildcard matches '/'                */
#define FNM_NOESCAPE    (1 << 1)  /* backslash is an ordinary character     */
#define FNM_PERIOD      (1 << 2)  /* a leading '.' must be matched literally*/
#define FNM_FILE_NAME   FNM_PATHNAME
#define FNM_LEADING_DIR (1 << 3)  /* pattern may match a leading directory  */
#define FNM_CASEFOLD    (1 << 4)  /* compare case-insensitively             */

#define FNM_NOMATCH 1

/* FNM_EXTMATCH (ksh @(...)|!(...) patterns) is deliberately NOT defined. A
   caller that tests `#ifdef FNM_EXTMATCH' then gets the right answer -- absent
   -- instead of passing a flag that would be silently ignored and quietly
   match the wrong files. */

int fnmatch(const char *pattern, const char *string, int flags);

#endif
