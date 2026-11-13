/* The crtl surface dropbear 2026.94 needed, against glibc on the same source
 * (feature-c-dropbear-builds-with-pxx). Each row is a function or header
 * that was missing or a stub:
 *
 *   strlcpy/strlcat  return value = the length tried, truncation, the
 *                    no-NUL-in-size case of strlcat
 *   explicit_bzero   the bytes are zero afterwards
 *   <shadow.h>       sgetspent parses all nine fields; empty numeric = -1
 *   <pty.h>          openpty gives a /dev/pts slave that isatty
 *   <utmp.h>         struct utmp / lastlog are glibc's sizes (a file format)
 *   <sys/time.h>     timeradd carries usec into sec; timerisset, timercmp
 *   getusershell     answers at least one shell (from /etc/shells or the
 *                    built-in /bin/sh fallback)
 *   getresuid        agrees with getuid/geteuid
 *   setuid           was an ENOSYS stub: setuid(own uid) now succeeds, and
 *                    setuid(0) as non-root fails with EPERM (when run as root
 *                    it succeeds, so that row prints the uid it ran as)
 *   sockaddr_storage 128 bytes, aligned for a long, ss_family first
 *
 * getspnam() is NOT a row: glibc answers through NSS (systemd-userdb can
 * hand out a shadow entry to non-root), crtl reads /etc/shadow only, and
 * that difference is deliberate (see lib/crtl/src/pwd.c).
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <string.h>
#include <stddef.h>
#include <unistd.h>
#include <errno.h>
#include <shadow.h>
#include <pty.h>
#include <utmp.h>
#include <sys/time.h>
#include <sys/types.h>
#include <sys/socket.h>

struct ss_wrap { char c; struct sockaddr_storage s; };

int main(void)
{
  char b[8];
  size_t r;
  struct spwd *s;
  int m, sl, rr, n = 0;
  char name[64];
  struct timeval a = {1, 900000}, c = {0, 200000}, d;
  uid_t ru, eu, su;
  char *sh;

  r = strlcpy(b, "hello world", sizeof b);
  printf("strlcpy %zu '%s'\n", r, b);
  r = strlcat(b, "xyz", sizeof b);
  printf("strlcat %zu '%s'\n", r, b);
  strcpy(b, "ab");
  r = strlcat(b, "cd", sizeof b);
  printf("strlcat2 %zu '%s'\n", r, b);
  memset(b, 'x', sizeof b);
  r = strlcat(b, "cd", 4);
  printf("strlcat_nonul %zu\n", r);
  explicit_bzero(b, sizeof b);
  printf("bzero %d\n", b[0] + b[7]);

  s = sgetspent("alice:$6$x$y:19000::99999:7:::\n");
  printf("spwd %s %s %ld %ld %ld %ld %ld %ld\n", s->sp_namp, s->sp_pwdp,
         s->sp_lstchg, s->sp_min, s->sp_max, s->sp_warn, s->sp_inact, s->sp_expire);

  if (openpty(&m, &sl, name, 0, 0) == 0)
    printf("openpty ok %s istty=%d\n",
           strncmp(name, "/dev/pts/", 9) == 0 ? "pts" : name, isatty(sl));
  else
    printf("openpty fail %d\n", errno);

  printf("sizeof utmp %zu lastlog %zu\n", sizeof(struct utmp), sizeof(struct lastlog));

  timeradd(&a, &c, &d);
  printf("timeradd %ld.%06ld set=%d lt=%d\n", (long)d.tv_sec, (long)d.tv_usec,
         timerisset(&d) ? 1 : 0, timercmp(&c, &a, <) ? 1 : 0);

  setusershell();
  while ((sh = getusershell()) != NULL) n++;
  endusershell();
  printf("shells>0 %d\n", n > 0);

  rr = getresuid(&ru, &eu, &su);
  printf("getresuid %d same=%d\n", rr, ru == getuid() && eu == geteuid() && su == geteuid());
  rr = setuid(getuid());
  printf("setuid(self) %d\n", rr);
  if (getuid() != 0) {
    errno = 0;
    rr = setuid(0);
    printf("setuid(0) %d eperm=%d\n", rr, errno == EPERM);
  } else {
    printf("setuid(0) ran as root\n");
  }

  printf("sockaddr_storage %zu align %zu family@%zu\n", sizeof(struct sockaddr_storage),
         offsetof(struct ss_wrap, s), offsetof(struct sockaddr_storage, ss_family));
  return 0;
}
