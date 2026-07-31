/* crtl against gcc's libc, which is the oracle this surface is built to match
   (feature-crtl-implement-libc-assumptions: "keep gcc's libc as the oracle for
   behaviour").

   Every line of output is compared to the SAME file built by gcc -- there are
   no recorded expectations here, because a recorded expectation for a libc
   surface is just our own behaviour written down, and this ticket exists
   precisely because "it links" is not the same as "it agrees".

   The batch is the one a census of declared-but-possibly-unimplemented symbols
   turned up: strtoll/strtoull/atoll/atof (bases, sign, endptr, overflow clamp),
   the whole wide-ctype family, math edges where sign and rounding differ, and
   the PRI/SCN round trip -- the last because a wrong length modifier is
   varargs, so it reads the wrong bytes off the stack with no diagnostic
   anywhere. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <wctype.h>
#include <wchar.h>
#include <ctype.h>
#include <inttypes.h>
#include <limits.h>
#include <stdint.h>
#include <stddef.h>
#include <errno.h>

static int cmp(const void *x, const void *y) { return *(const int*)x - *(const int*)y; }

int main(void) {
  /* strtoll / strtoull: bases, sign, overflow clamp, endptr */
  char *e;
  printf("strtoll-10=%lld\n", strtoll("  -1234abc", &e, 10));
  printf("strtoll-endp=%s\n", e);
  printf("strtoll-16=%lld\n", strtoll("0x1f", &e, 16));
  printf("strtoll-0=%lld\n", strtoll("0755", &e, 0));
  printf("strtoll-max=%lld\n", strtoll("9223372036854775807", &e, 10));
  printf("strtoll-ovf=%lld\n", strtoll("9223372036854775808", &e, 10));
  printf("strtoull-max=%llu\n", strtoull("18446744073709551615", &e, 10));
  printf("strtoull-neg=%llu\n", strtoull("-1", &e, 10));
  printf("atoll=%lld\n", atoll("  42xyz"));
  printf("atof=%.6f\n", atof(" -3.5e2rest"));

  /* wide ctype */
  printf("isw=%d%d%d%d%d%d%d%d%d%d%d%d\n",
    !!iswalnum(L'a'), !!iswalpha(L'1'), !!iswblank(L'\t'), !!iswcntrl(L'\n'),
    !!iswdigit(L'7'), !!iswgraph(L' '), !!iswlower(L'Z'), !!iswprint(L'\t'),
    !!iswpunct(L','), !!iswspace(L'\v'), !!iswupper(L'Q'), !!iswxdigit(L'F'));
  printf("towl=%d towu=%d towl9=%d\n", (int)towlower(L'Q'), (int)towupper(L'q'), (int)towlower(L'9'));
  printf("wcslen=%d\n", (int)wcslen(L"abcde"));

  /* math edges */
  printf("fmod=%.6f %.6f %.6f\n", fmod(7.5, 2.0), fmod(-7.5, 2.0), fmod(7.5, -2.0));
  printf("hypot=%.6f %.6f\n", hypot(3.0, 4.0), hypot(-5.0, 12.0));
  printf("log2=%.6f %.6f\n", log2(1024.0), log2(0.5));
  printf("log10=%.6f\n", log10(1e6));
  printf("exp2=%.6f %.6f\n", exp2(10.0), exp2(-2.0));
  printf("sinh=%.6f cosh=%.6f tanh=%.6f\n", sinh(1.0), cosh(1.0), tanh(1.0));
  printf("fabsf=%.6f\n", (double)fabsf(-1.25f));
  printf("ceilfloor=%.1f %.1f %.1f %.1f\n", ceil(1.2), ceil(-1.2), floor(1.8), floor(-1.8));

  /* bsearch + qsort ordering */
  int a[] = {1, 3, 5, 7, 9, 11};
  int key = 7;
  int *hit = (int*)bsearch(&key, a, 6, sizeof(int), cmp);
  printf("bsearch=%d\n", hit ? *hit : -1);
  key = 8;
  hit = (int*)bsearch(&key, a, 6, sizeof(int), cmp);
  printf("bsearch-miss=%d\n", hit ? *hit : -1);

  /* Widths and limits: what real C branches on. A wrong one here is an ABI
     mismatch, not a wrong answer, so it is worth pinning against gcc. */
  printf("sz int=%d long=%d llong=%d ptr=%d size_t=%d ptrdiff=%d\n",
    (int)sizeof(int), (int)sizeof(long), (int)sizeof(long long),
    (int)sizeof(void*), (int)sizeof(size_t), (int)sizeof(ptrdiff_t));
  printf("sz int8=%d int16=%d int32=%d int64=%d intptr=%d intmax=%d wchar=%d\n",
    (int)sizeof(int8_t), (int)sizeof(int16_t), (int)sizeof(int32_t),
    (int)sizeof(int64_t), (int)sizeof(intptr_t), (int)sizeof(intmax_t),
    (int)sizeof(wchar_t));
  printf("CHAR_BIT=%d CHAR_MIN=%d CHAR_MAX=%d char-signed=%d\n",
    CHAR_BIT, CHAR_MIN, CHAR_MAX, (char)-1 < 0);
  printf("INT=%d/%d UINT=%u\n", INT_MIN, INT_MAX, UINT_MAX);
  printf("LONG=%lld/%lld ULONG=%llu\n",
    (long long)LONG_MIN, (long long)LONG_MAX, (unsigned long long)ULONG_MAX);
  printf("LLONG=%lld/%lld ULLONG=%llu\n", LLONG_MIN, LLONG_MAX, ULLONG_MAX);
  printf("INT64=%lld/%lld UINT64=%llu SIZE_MAX=%llu\n",
    (long long)INT64_MIN, (long long)INT64_MAX,
    (unsigned long long)UINT64_MAX, (unsigned long long)SIZE_MAX);

  /* errno NAMES. These are an ABI, and a MISSING one is worse than a wrong
     one: an undeclared identifier is "treated as 0", so `errno == ECONNREFUSED`
     became `errno == 0` -- the SUCCESS value, so the branch fired exactly when
     it should not have. 39 of these were in that state. */
  printf("errno1 %d %d %d %d %d %d %d %d %d %d\n",
    EPERM, ENOENT, ESRCH, EINTR, EIO, ENXIO, E2BIG, ENOEXEC, EBADF, ECHILD);
  printf("errno2 %d %d %d %d %d %d %d %d %d %d\n",
    EAGAIN, ENOMEM, EACCES, EFAULT, ENOTBLK, EBUSY, EEXIST, EXDEV, ENODEV, ENOTDIR);
  printf("errno3 %d %d %d %d %d %d %d %d %d %d\n",
    EISDIR, EINVAL, ENFILE, EMFILE, ENOTTY, ETXTBSY, EFBIG, ENOSPC, ESPIPE, EROFS);
  printf("errno4 %d %d %d %d %d %d %d %d %d %d\n",
    EMLINK, EPIPE, EDOM, ERANGE, EDEADLK, ENAMETOOLONG, ENOLCK, ENOSYS, ENOTEMPTY, ELOOP);
  printf("errno5 %d %d %d %d %d %d %d %d %d %d\n",
    EWOULDBLOCK, ENOMSG, EIDRM, EOVERFLOW, EILSEQ, ENOTSOCK, EDESTADDRREQ,
    EMSGSIZE, EPROTOTYPE, ENOPROTOOPT);
  printf("errno6 %d %d %d %d %d %d %d %d %d %d\n",
    EPROTONOSUPPORT, EOPNOTSUPP, ENOTSUP, EAFNOSUPPORT, EADDRINUSE,
    EADDRNOTAVAIL, ENETDOWN, ENETUNREACH, ENETRESET, ECONNABORTED);
  printf("errno7 %d %d %d %d %d %d %d %d %d %d\n",
    ECONNRESET, ENOBUFS, EISCONN, ENOTCONN, ETIMEDOUT, ECONNREFUSED,
    EHOSTDOWN, EHOSTUNREACH, EALREADY, EINPROGRESS);
  printf("errno8 %d\n", ECANCELED);

  /* PRI/SCN round trip */
  int64_t v = -1234567890123LL;
  char buf[64];
  sprintf(buf, "%" PRId64, v);
  printf("PRId64=%s\n", buf);
  int64_t back = 0;
  sscanf(buf, "%" SCNd64, &back);
  printf("SCNd64=%d\n", back == v);
  return 0;
}
