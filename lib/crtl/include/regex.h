/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <regex.h> -- POSIX regular expressions.
 *
 * THE VALUES ARE glibc's AND THE STRUCT IS NOT, deliberately, and the two
 * halves are decided by different questions. The cflag/eflag/error NUMBERS are
 * glibc's because a program may write `REG_EXTENDED | REG_ICASE' as a literal
 * or compare regexec's answer against a remembered 1, and matching costs
 * nothing (measured against this box's glibc, 2026-09-02: REG_EXTENDED 1,
 * REG_ICASE 2, REG_NEWLINE 4, REG_NOSUB 8; REG_NOTBOL 1, REG_NOTEOL 2,
 * REG_STARTEND 4; REG_NOMATCH 1 through REG_BADRPT 13, on both widths).
 * `struct re_pattern_buffer' is NOT glibc's -- glibc's is 64 bytes on x86-64
 * and 32 on i386, ours is neither -- because POSIX makes every member but
 * re_nsub implementation-defined and a crtl program compiles against THIS
 * header. Copying a layout no crtl program can observe would only oblige us to
 * keep fields true that nothing reads. Same call as <sys/sem.h>'s semid_ds.
 *
 * regoff_t IS `int' ON BOTH WIDTHS. That was measured, not assumed: glibc's is
 * 4 bytes for x86-64 as well as i386, so regmatch_t is 8 bytes either way and
 * a `%d' on rm_so is right everywhere. It is the one type here that does NOT
 * follow the pointer width, and busybox prints and does arithmetic on these
 * offsets in 47 places.
 *
 * THE TYPE IS SPELLED `struct re_pattern_buffer' AND NOT AN ANONYMOUS STRUCT
 * because busybox names it directly: findutils/grep.c and editors/vi.c both
 * declare one when CONFIG_EXTRA_COMPAT / CONFIG_FEATURE_VI_REGEX_SEARCH are
 * on. Those two options are OFF in the config we build, so the rest of the GNU
 * surface they want -- re_syntax_options, re_compile_pattern, re_search,
 * struct re_registers -- is deliberately absent; adding a stub would compile
 * their arms and then behave wrongly at run time, which is worse than the
 * `undeclared' they get now.
 *
 * Found attempting busybox on i386, where it is the largest single blocker:
 * seven translation units (awk, sed, grep, expr, test, mdev and the
 * libbb/xregcomp.c wrapper the others go through).
 * feature-c-crtl-posix-regex-regcomp-regexec
 */
#ifndef _CRTL_REGEX_H
#define _CRTL_REGEX_H

#include <sys/types.h>   /* size_t */

/* Measured against glibc: 4 bytes on x86-64 AND i386. Not the pointer width. */
typedef int regoff_t;

typedef struct {
  regoff_t rm_so;   /* byte offset of the match start, -1 if unused */
  regoff_t rm_eo;   /* byte offset one past the match end */
} regmatch_t;

struct re_pattern_buffer {
  size_t re_nsub;    /* POSIX: parenthesised subexpressions in the pattern */
  void  *__prog;     /* crtl-private compiled program */
  int    __cflags;   /* the cflags regcomp was given */
  int    __nnodes;   /* nodes in __prog, for the interpreter's bounds checks */
};
typedef struct re_pattern_buffer regex_t;

/* cflags for regcomp. */
#define REG_EXTENDED  1   /* ERE rather than BRE -- a DIFFERENT LANGUAGE */
#define REG_ICASE     2   /* case-insensitive */
#define REG_NEWLINE   4   /* . and [^...] do not match newline; ^/$ anchor at one */
#define REG_NOSUB     8   /* report only whether it matched */

/* eflags for regexec. */
#define REG_NOTBOL    1   /* the start of `string' is not the start of a line */
#define REG_NOTEOL    2   /* the end of `string' is not the end of a line */
#define REG_STARTEND  4   /* BSD/GNU: pmatch[0] delimits the region to search */

/* Return values. REG_NOERROR is 0 so `if (regexec(...))' reads correctly. */
#define REG_NOERROR   0
#define REG_NOMATCH   1
#define REG_BADPAT    2   /* invalid pattern */
#define REG_ECOLLATE  3   /* invalid collating element */
#define REG_ECTYPE    4   /* invalid character class name */
#define REG_EESCAPE   5   /* trailing backslash */
#define REG_ESUBREG   6   /* invalid back reference */
#define REG_EBRACK    7   /* unmatched [ or [^ */
#define REG_EPAREN    8   /* unmatched ( or \( */
#define REG_EBRACE    9   /* unmatched { or \{ */
#define REG_BADBR    10   /* invalid content of {} */
#define REG_ERANGE   11   /* invalid range end */
#define REG_ESPACE   12   /* out of memory */
#define REG_BADRPT   13   /* repetition operator with nothing to repeat */

int    regcomp(regex_t *preg, const char *pattern, int cflags);
int    regexec(const regex_t *preg, const char *string, size_t nmatch,
               regmatch_t pmatch[], int eflags);
size_t regerror(int errcode, const regex_t *preg, char *errbuf,
                size_t errbuf_size);
void   regfree(regex_t *preg);

#endif
