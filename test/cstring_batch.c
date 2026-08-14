/* The assumed-libc batch (feature-crtl-libc-gap-batch-2026-08): stpcpy,
 * memccpy, memrchr, strsep, strcasestr, strdup, strndup, setenv, unsetenv.
 *
 * Compiling is not the same as being correct, so this is a BEHAVIOURAL test and
 * the whole output is diffed against the same file built by gcc — there are no
 * recorded expectations to drift. The cases are chosen where these functions
 * differ from their obvious cousins, because that is where a plausible wrong
 * implementation hides:
 *
 *   stpcpy   returns the NUL, not the start (vs strcpy)
 *   memccpy  stops AFTER the first c, and yields NULL when c is absent
 *   memrchr  walks backwards; n = 0 must not read at all
 *   strsep   yields an EMPTY token between adjacent delimiters (vs strtok)
 *   strndup  NUL-terminates even when the source is longer than n
 *   setenv   with overwrite = 0 must NOT replace an existing value
 */
/* memrchr, strsep and strcasestr are GNU extensions: glibc only declares them
 * when _GNU_SOURCE is defined. Without it the gcc ORACLE builds on an implicit
 * declaration, which GCC 14 turned from a warning into an error — so the oracle
 * stops building and the diff step reports it as a pxx divergence.
 * ([[bug-b-cstring-batch-gcc-oracle-does-not-build-on-gcc-14]]) */
#define _GNU_SOURCE
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

int main(void) {
  char buf[32], *p, *q;
  const char *s;
  char work[32];

  /* stpcpy returns the END */
  p = stpcpy(buf, "abc");
  printf("stpcpy ret_off=%d buf=[%s]\n", (int)(p - buf), buf);
  /* chaining is the reason it exists */
  p = stpcpy(stpcpy(buf, "ab"), "cd");
  printf("stpcpy chain=[%s] off=%d\n", buf, (int)(p - buf));

  /* memccpy: found vs not found */
  memset(buf, '.', sizeof buf);
  p = (char *)memccpy(buf, "hello", 'l', 5);
  printf("memccpy found_off=%d first4=%c%c%c%c\n",
         p ? (int)(p - buf) : -1, buf[0], buf[1], buf[2], buf[3]);
  memset(buf, '.', sizeof buf);
  p = (char *)memccpy(buf, "hello", 'z', 5);
  printf("memccpy absent=%d\n", p == 0);

  /* memrchr: last occurrence, and the empty case */
  s = "abcabc";
  p = (char *)memrchr(s, 'b', 6);
  printf("memrchr off=%d\n", p ? (int)(p - s) : -1);
  p = (char *)memrchr(s, 'b', 0);
  printf("memrchr n0=%d\n", p == 0);

  /* strsep: EMPTY token between adjacent delimiters (strtok would skip it) */
  strcpy(work, "a::b");
  q = work;
  while ((p = strsep(&q, ":")) != 0) printf("strsep [%s]\n", p);
  printf("strsep end_null=%d\n", q == 0);

  /* strcasestr */
  p = strcasestr("Hello World", "WORLD");
  printf("strcasestr off=%d\n", p ? (int)(p - "Hello World") : -1);
  printf("strcasestr empty_needle=%d absent=%d\n",
         strcasestr("abc", "") != 0, strcasestr("abc", "zz") == 0);

  /* strdup / strndup */
  p = strdup("duplicate");
  printf("strdup=[%s] len=%d\n", p, (int)strlen(p));
  free(p);
  p = strndup("truncate-me", 4);
  printf("strndup=[%s] len=%d\n", p, (int)strlen(p));
  free(p);
  p = strndup("ab", 8);            /* n longer than the source */
  printf("strndup_short=[%s] len=%d\n", p, (int)strlen(p));
  free(p);

  /* setenv / unsetenv, including the overwrite=0 contract */
  setenv("PXX_BATCH_VAR", "first", 1);
  printf("setenv1=[%s]\n", getenv("PXX_BATCH_VAR"));
  setenv("PXX_BATCH_VAR", "second", 0);            /* must NOT replace */
  printf("setenv_no_overwrite=[%s]\n", getenv("PXX_BATCH_VAR"));
  setenv("PXX_BATCH_VAR", "third", 1);             /* must replace */
  printf("setenv_overwrite=[%s]\n", getenv("PXX_BATCH_VAR"));
  /* a name must not match a longer one */
  setenv("PXX_BATCH_VAR_EXT", "ext", 1);
  printf("no_prefix=[%s][%s]\n",
         getenv("PXX_BATCH_VAR"), getenv("PXX_BATCH_VAR_EXT"));
  unsetenv("PXX_BATCH_VAR");
  printf("unset=%d sibling=[%s]\n",
         getenv("PXX_BATCH_VAR") == 0, getenv("PXX_BATCH_VAR_EXT"));
  /* rejected inputs */
  printf("bad=%d %d\n", setenv("HAS=EQUALS", "x", 1), setenv("", "x", 1));

  return 0;
}
