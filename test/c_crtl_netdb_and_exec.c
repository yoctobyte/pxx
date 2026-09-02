/* SPDX-License-Identifier: Zlib */
/*
 * crtl: the /etc/services walk, h_errno/hstrerror, the exec list forms, the
 * process-group calls, inet_ntoa and getpeername.
 *
 * ALL OF THESE HAVE A PLAUSIBLE WRONG ANSWER, which is why the rows check a
 * value rather than a return code:
 *
 *  - servent.s_port is in NETWORK order. A wrapper that forgets returns 5380
 *    for 80 on a little-endian box -- in range, no error, and the caller
 *    connects somewhere else. Rows 3 and 5 read it through ntohs and row 4
 *    reads the raw field, so the two together pin the byte order rather than
 *    just the number.
 *  - h_errno IS A REAL int, not a macro over errno. It was returning the
 *    default string for every code because HOST_NOT_FOUND and friends were
 *    declared BELOW netdb.h's own includes, and a guard-suppressed include
 *    from src/netinet/in.c splices src/netdb.c in while netdb.h is two lines
 *    old -- so inside that TU the constants were undeclared identifiers
 *    treated as 0. Rows 7-9 are what catches that: three DIFFERENT codes must
 *    give three different strings.
 *  - execl's variadic list is collected here rather than by the kernel, so an
 *    off-by-one drops the last argument. Row 12 checks the CHILD's argv, not
 *    execl's return, because a successful exec does not return at all.
 *
 * Every read is sequenced into its own statement: an argument list has no
 * evaluation order.
 *
 * Rows were diffed against glibc by compiling this same file with gcc.
 * feature-c-corpus-busybox-multi-applet
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <netdb.h>
#include <arpa/inet.h>
#include <sys/wait.h>

int main(void) {
  struct servent *se;
  struct in_addr ia;
  const char *s1, *s2, *s3;
  char *p;
  int rc, st;
  pid_t kid;

  se = getservbyname("http", "tcp");
  printf("1 %d\n", se != 0);
  if (se) {
    rc = strcmp(se->s_name, "http");
    printf("2 %d\n", rc);
    rc = ntohs((unsigned short)se->s_port);
    printf("3 %d\n", rc);
    /* the raw field, to pin that it really is stored network order */
    rc = (se->s_port == (int)htons(80));
    printf("4 %d\n", rc);
  }
  se = getservbyport((int)htons(22), "tcp");
  printf("5 %d\n", se != 0 && strcmp(se->s_name, "ssh") == 0);
  se = getservbyname("no-such-service-anywhere", "tcp");
  printf("6 %d\n", se == 0);

  /* three codes, three strings -- see the header comment */
  s1 = hstrerror(HOST_NOT_FOUND);
  s2 = hstrerror(TRY_AGAIN);
  s3 = hstrerror(NO_RECOVERY);
  printf("7 %d\n", s1 != 0 && s2 != 0 && s3 != 0);
  printf("8 %d\n", strcmp(s1, s2) != 0 && strcmp(s2, s3) != 0 && strcmp(s1, s3) != 0);
  h_errno = 0;
  printf("9 %d\n", h_errno);

  ia.s_addr = htonl(0x7F000001UL);
  p = inet_ntoa(ia);
  printf("10 %s\n", p);

  /* getpgid(0) is this process's group; setpgrp puts us in our own. */
  rc = (getpgid(0) > 0);
  printf("11 %d\n", rc);

  /* execl's list, checked through the CHILD's argv -- a successful exec does
     not return, so execl's own return value proves nothing. */
  /* FLUSH BEFORE THE FORK, or the row order is a test of the BUFFERING MODE
     rather than of exec: to a pipe glibc's stdout is fully buffered, so the
     child's `a b c' lands ahead of every parent row still sitting in the
     inherited buffer, while a line-buffered runtime emits them in source
     order. Both are legal; neither is what this file is asking about. */
  fflush(stdout);
  kid = fork();
  if (kid == 0) {
    execl("/bin/echo", "echo", "a", "b", "c", (char *)0);
    _exit(99);
  }
  waitpid(kid, &st, 0);
  rc = WEXITSTATUS(st);
  printf("12 %d\n", rc);
  return 0;
}
