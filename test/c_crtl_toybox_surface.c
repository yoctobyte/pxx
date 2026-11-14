/* The crtl surface toybox 0.8.15 needed (feature-c-toybox-builds-with-pxx):
   the *at family over real directory descriptors, sysconf/pathconf/confstr,
   nl_langinfo and newlocale, the C-locale wide-char set, utmpx, getifaddrs,
   posix_fadvise, getentropy, siginfo's layout, iconv, eventfd, prlimit,
   getcwd(NULL, 0) and getopt's '+'/'-' ordering prefixes. Expected output is
   gcc's (glibc), on x86-64 and i386. argv[1] is a scratch directory that must
   not exist. */
#define _GNU_SOURCE
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>
#include <signal.h>
#include <locale.h>
#include <langinfo.h>
#include <wchar.h>
#include <utmpx.h>
#include <ifaddrs.h>
#include <stddef.h>
#include <stdlib.h>
#include <iconv.h>
#include <sys/eventfd.h>
#include <sys/resource.h>
int main(int argc, char **argv) {
  const char *base = argc > 1 ? argv[1] : "/tmp/x";
  struct stat a, b; char buf[64]; int d, f; ssize_t n;
  mkdir(base, 0755);
  d = open(base, O_RDONLY | O_DIRECTORY);
  printf("mkdirat %d\n", mkdirat(d, "sub", 0700));
  f = openat(d, "sub/f", O_CREAT | O_WRONLY, 0640); printf("openat ok %d\n", f >= 0);
  write(f, "hello", 5); close(f);
  printf("symlinkat %d\n", symlinkat("sub/f", d, "ln"));
  { int r = fstatat(d, "ln", &a, 0); printf("fstatat %d size %ld mode %o\n", r, (long)a.st_size, a.st_mode & 07777); }
  { int r = fstatat(d, "ln", &a, AT_SYMLINK_NOFOLLOW); printf("fstatat nofollow %d islnk %d\n", r, S_ISLNK(a.st_mode)); }
  fstatat(d, "sub/f", &a, 0); { char p[300]; snprintf(p, sizeof p, "%s/sub/f", base); stat(p, &b); }
  printf("same dev/ino %d %d nlink %ld\n", a.st_dev == b.st_dev, a.st_ino == b.st_ino, (long)a.st_nlink);
  n = readlinkat(d, "ln", buf, sizeof buf); buf[n > 0 ? n : 0] = 0; printf("readlinkat %ld %s\n", (long)n, buf);
  printf("faccessat %d %d\n", faccessat(d, "sub/f", R_OK, 0), faccessat(d, "nope", F_OK, AT_SYMLINK_NOFOLLOW));
  printf("fchmodat %d\n", fchmodat(d, "sub/f", 0600, 0)); fstatat(d, "sub/f", &a, 0); printf("mode %o\n", a.st_mode & 07777);
  printf("renameat %d\n", renameat(d, "sub/f", d, "sub/g"));
  printf("linkat %d\n", linkat(d, "sub/g", d, "hl", 0));
  { int r1 = unlinkat(d, "ln", 0), r2 = unlinkat(d, "hl", 0), r3 = unlinkat(d, "sub/g", 0), r4 = unlinkat(d, "sub", AT_REMOVEDIR); printf("unlinkat %d %d %d %d\n", r1, r2, r3, r4); }
  { int r; errno = 0; r = unlinkat(d, "zz", 0); printf("unlinkat missing %d errno %d\n", r, errno); }
  close(d); rmdir(base);
  printf("sc %d %d %d\n", sysconf(_SC_ARG_MAX) >= 131072, sysconf(_SC_NPROCESSORS_ONLN) > 0, sysconf(_SC_PHYS_PAGES) > 1000);
  printf("pc %ld %ld\n", pathconf("/", _PC_NAME_MAX), pathconf("/nonexist", _PC_NAME_MAX));
  { char cs[64]; size_t k = confstr(_CS_PATH, cs, sizeof cs); printf("confstr %zu %s\n", k, cs); }
  printf("codeset %s\n", nl_langinfo(CODESET));
  printf("newlocale C %d bogus %d\n", newlocale(LC_CTYPE_MASK, "C", 0) != 0, newlocale(LC_CTYPE_MASK, "xx_YY", 0) != 0);
  { mbstate_t st; char o[4]; memset(&st, 0, sizeof st); printf("wc %d %d %d %d %ld %ld\n", wcwidth('A'), wcwidth(0), wcwidth(7), wcwidth(0xe9), (long)wcrtomb(o, 'x', &st), (long)wcrtomb(o, 0xe9, &st)); }
  printf("getentropy %d %d\n", getentropy(buf, 32), getentropy(buf, 300 + (argc > 99)));
  { int lp = sizeof(long) == 8; printf("siginfo layout %d\n", sizeof(siginfo_t) == 128 && offsetof(siginfo_t, si_status) == (lp ? 24u : 20u) && offsetof(siginfo_t, si_addr) == (lp ? 16u : 12u) && offsetof(siginfo_t, si_pid) == (lp ? 16u : 12u)); }
  setutxent(); { int k = 0; while (getutxent()) k++; printf("utmpx readable %d\n", k >= 0); } endutxent();
  { struct ifaddrs *ia, *p; int lo = 0; if (getifaddrs(&ia) == 0) { for (p = ia; p; p = p->ifa_next) if (!strcmp(p->ifa_name, "lo") && p->ifa_addr->sa_family == AF_INET) lo = 1; freeifaddrs(ia); } printf("ifaddrs lo %d\n", lo); }
  printf("fadvise %d\n", posix_fadvise(0, 0, 0, POSIX_FADV_NORMAL) != EBADF);
  { iconv_t cd = iconv_open("UTF-16LE", "utf8"); char in[] = "a\xc3\xa9\xe2\x82\xac", out[16], *ip = in, *op = out; size_t il = 6, ol = sizeof out, r, k;
    r = iconv(cd, &ip, &il, &op, &ol); printf("iconv %ld %ld:", (long)r, (long)(sizeof out - ol)); for (k = 0; k < sizeof out - ol; k++) printf(" %02x", (unsigned char)out[k]); printf("\n"); iconv_close(cd);
    cd = iconv_open("ASCII", "UTF-8"); ip = in; il = 6; op = out; ol = sizeof out; errno = 0; r = iconv(cd, &ip, &il, &op, &ol); printf("iconv ascii %ld errno %d left %ld\n", (long)r, errno, (long)il); iconv_close(cd);
    printf("iconv bogus %d\n", iconv_open("NOPE-9", "UTF-8") == (iconv_t)-1); }
  { int fd = eventfd(2, EFD_CLOEXEC); eventfd_t v = 0; eventfd_write(fd, 5); eventfd_read(fd, &v); printf("eventfd %llu\n", (unsigned long long)v); close(fd); }
  { struct rlimit a, b; int r1 = prlimit(0, RLIMIT_NOFILE, 0, &a), r2 = getrlimit(RLIMIT_NOFILE, &b); printf("prlimit %d %d same %d\n", r1, r2, a.rlim_cur == b.rlim_cur && a.rlim_max == b.rlim_max); }
  { char *c1 = getcwd(NULL, 0), c2[4096]; getcwd(c2, sizeof c2); printf("getcwd null %d\n", c1 && !strcmp(c1, c2)); free(c1); }
  { char *t1[] = {"p", "-a", "x", "-l", "y"}; int o, n = 0; optind = 0; opterr = 0; while ((o = getopt(5, t1, "+a")) != -1) n++; printf("getopt + %d %d\n", n, optind);
    optind = 0; n = 0; while ((o = getopt(5, t1, "-a")) != -1) n += o == 1; printf("getopt - %d %d\n", n, optind); }
  return 0;
}
