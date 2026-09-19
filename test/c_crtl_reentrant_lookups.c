/* The six reentrant lookups that did not exist until this test's commit:
   getpwnam_r, getpwuid_r, getgrnam_r, getgrgid_r, getservbyname_r, rand_r.

   WHY THE ASSERTIONS ARE RELATIONS AND NOT VALUES. This file cannot assert
   root's shell or ssh's port: they differ per machine, and a fixture carrying
   a per-system constant is red on somebody else's box for no defect. Every row
   below compares the _r answer against the PLAIN answer on the same input, so
   it carries no expected value and still fails if the two disagree.

   AND WHY THAT ALONE IS NOT ENOUGH. A "reentrant" function that simply called
   the plain one and returned its STATIC pointer would pass every agreement row
   above -- that is the whole bug class these functions exist to remove. So the
   load-bearing assertion is a different one: the strings the _r form returns
   must live INSIDE THE CALLER'S BUFFER, and the plain form's must not. That is
   a property no stub and no static-returning fake can fake, and it is checked
   by address rather than by content.

   The third row is the one that proves they are independent rather than merely
   copied: two buffers filled by two calls must BOTH still be valid afterwards.
   With static storage the first is clobbered by the second, which is exactly
   the failure a threaded program hits.

   RUN UNDER gcc IT FAILS ONE ROW ON PURPOSE -- the not-found return value,
   where glibc deviates from POSIX. See that row. Everything else passed
   against glibc when this was written, which is what makes the rest of the
   file an oracle-checked reading of the contract rather than my own.

   bug-c-six-reentrant-libc-variants-do-not-exist-so-threaded-c-has-no-correct-call */
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <pwd.h>
#include <grp.h>
#include <netdb.h>
#include <stdlib.h>

#define INBUF(p, b) ((const char *)(p) >= (b) && (const char *)(p) < (b) + sizeof (b))

static int fails = 0;
static void ck(const char *what, int ok) {
  if (!ok) { printf("FAIL %s\n", what); fails++; }
}

int main(void) {
  char b1[4096], b2[4096];
  struct passwd pw1, pw2, *pr1, *pr2, *plain;
  struct group  gr1, *grr, *gplain;
  struct servent se, *ser, *splain;
  unsigned int s1, s2;
  int rc, i, a, bb;

  /* ---- getpwnam_r: agrees with the plain form, and owns its storage ------ */
  rc = getpwnam_r("root", &pw1, b1, sizeof b1, &pr1);
  ck("getpwnam_r rc", rc == 0);
  plain = getpwnam("root");
  ck("getpwnam_r found root", pr1 != 0);
  ck("getpwnam agrees", plain != 0 && pr1 != 0 && strcmp(plain->pw_name, pr1->pw_name) == 0
                        && plain->pw_uid == pr1->pw_uid);
  /* the discriminator: _r's strings are in MY buffer, the plain one's are not */
  ck("getpwnam_r uses the caller's buffer", pr1 && INBUF(pr1->pw_name, b1));
  ck("getpwnam does not", plain && !INBUF(plain->pw_name, b1));

  /* ---- two buffers stay independent ------------------------------------- */
  rc = getpwuid_r((uid_t)0, &pw2, b2, sizeof b2, &pr2);
  ck("getpwuid_r rc", rc == 0 && pr2 != 0);
  ck("both results still valid", pr1 && pr2 && strcmp(pr1->pw_name, pr2->pw_name) == 0);
  ck("and they are separate objects", pr1 != pr2 && pr1->pw_name != pr2->pw_name);

  /* ---- not found ---------------------------------------------------------
     THE ONE ROW WHERE THE gcc/glibc ORACLE DISAGREES WITH US, measured
     2026-09-19: glibc answers rc=2 (ENOENT), we answer rc=0. POSIX is explicit
     -- "if the requested entry is not found, 0 shall be returned and result
     shall be set to a null pointer" -- and Linux's own getpwnam_r(3) records
     that implementations deviate. We follow POSIX, and the choice is also the
     SAFER direction rather than merely the purer one: both set *result to
     NULL, so the portable idiom (`... , &r); if (!r) not_found;') works under
     either, while code that treats any nonzero rc as a hard error gets a hard
     error from glibc on an ordinary missing user and not from us.

     DO NOT "FIX" THIS BY MATCHING glibc. Running this fixture under gcc fails
     exactly this row and nothing else; that is the divergence, not a bug, and
     the row is named so the failure explains itself. */
  rc = getpwnam_r("no.such.user.exists.hopefully", &pw2, b2, sizeof b2, &pr2);
  ck("missing user result==NULL (both agree)", pr2 == 0);
  ck("missing user rc==0 (POSIX; glibc deviates with ENOENT)", rc == 0);

  /* ---- a buffer too small is ERANGE, not a wrong answer ------------------ */
  {
    char tiny[8];
    struct passwd pwt, *prt;
    rc = getpwnam_r("root", &pwt, tiny, sizeof tiny, &prt);
    ck("tiny buffer gives ERANGE", rc == ERANGE);
    ck("tiny buffer sets no result", prt == 0);
  }

  /* ---- groups: same shape, plus the member array lives in the buffer ----- */
  rc = getgrgid_r((gid_t)0, &gr1, b1, sizeof b1, &grr);
  ck("getgrgid_r rc", rc == 0 && grr != 0);
  gplain = getgrgid((gid_t)0);
  ck("getgrgid agrees", gplain && grr && strcmp(gplain->gr_name, grr->gr_name) == 0);
  ck("getgrgid_r name in caller buffer", grr && INBUF(grr->gr_name, b1));
  ck("getgrgid_r member array in caller buffer", grr && INBUF(grr->gr_mem, b1));
  {
    struct group grn, *grnr;
    rc = getgrnam_r(grr ? grr->gr_name : "root", &grn, b2, sizeof b2, &grnr);
    ck("getgrnam_r round-trips the name", rc == 0 && grnr != 0
       && grr && grnr->gr_gid == grr->gr_gid);
  }

  /* ---- services: skipped when /etc/services has no entry, never asserted
         against a hardcoded port -------------------------------------------- */
  splain = getservbyname("ssh", "tcp");
  rc = getservbyname_r("ssh", "tcp", &se, b1, sizeof b1, &ser);
  ck("getservbyname_r rc", rc == 0);
  if (splain) {
    ck("getservbyname agrees", ser != 0 && ser->s_port == splain->s_port
       && strcmp(ser->s_name, splain->s_name) == 0);
    ck("getservbyname_r name in caller buffer", ser && INBUF(ser->s_name, b1));
    ck("getservbyname_r alias array in caller buffer", ser && INBUF(ser->s_aliases, b1));
  } else {
    ck("no ssh entry: _r must agree it is absent", ser == 0);
  }

  /* ---- rand_r: deterministic, in range, advances, and independent -------- */
  s1 = 12345; s2 = 12345;
  a = rand_r(&s1); bb = rand_r(&s2);
  ck("rand_r deterministic for a seed", a == bb);
  ck("rand_r advanced the seed", s1 != 12345u);
  s2 = 999;
  (void)rand_r(&s2);
  ck("rand_r seeds do not interfere", s1 != s2);
  for (i = 0; i < 1000; i++) {
    int v = rand_r(&s1);
    if (v < 0 || v > RAND_MAX) { ck("rand_r in [0,RAND_MAX]", 0); break; }
  }
  /* two successive calls differing is the check that separates a real
     generator from a stub returning a constant -- which would satisfy every
     range and determinism row above */
  s1 = 7;
  ck("rand_r is not a constant", rand_r(&s1) != rand_r(&s1));

  printf("fails=%d\n", fails);
  printf("%s\n", fails == 0 ? "C REENTRANT LOOKUPS OK" : "C REENTRANT LOOKUPS BROKEN");
  return 0;
}
