/* The BSD/glibc spellings TinyX's os/ and kdrive/ use: setlinebuf,
   getdtablesize, fd_mask/NFDBITS/__FDS_BITS, FNDELAY, the full struct lconv in glibc's
   member order, and <linux/fb.h> bringing __u16.
   feature-c-crtl-bsd-spellings-and-full-lconv */
#include <stdio.h>
#include <stddef.h>
#include <unistd.h>
#include <fcntl.h>
#include <locale.h>
#include <sys/select.h>
#include <linux/fb.h>

int main(void)
{
    struct lconv *lc = localeconv();
    fd_mask m = 1;
    __u16 red[4] = { 1, 2, 3, 65535 };
    setlinebuf(stdout);
    printf("dtable %s\n", getdtablesize() >= 64 ? "ok" : "small");
    printf("NFDBITS %d sizeof(fd_mask) %d m<<5 %ld\n", NFDBITS, (int)sizeof(fd_mask), (long)(m << 5));
    {
        fd_set fs;
        FD_ZERO(&fs);
        __FDS_BITS(&fs)[1] = 4;
        printf("fds %d %d\n", FD_ISSET(NFDBITS + 2, &fs), FD_ISSET(NFDBITS + 1, &fs));
    }
    printf("FNDELAY==O_NONBLOCK %d FASYNC==O_ASYNC %d F_SETOWN %d F_GETOWN %d\n", FNDELAY == O_NONBLOCK, FASYNC == O_ASYNC, F_SETOWN, F_GETOWN);
    printf("lconv size %d positive_sign@%d frac_digits@%d n_sign_posn@%d\n",
           (int)sizeof(struct lconv), (int)offsetof(struct lconv, positive_sign),
           (int)offsetof(struct lconv, frac_digits), (int)offsetof(struct lconv, n_sign_posn));
    printf("C locale: '%s' '%s' '%s' %d %d\n", lc->decimal_point, lc->positive_sign,
           lc->currency_symbol, lc->frac_digits, lc->int_n_sign_posn);
    printf("u16 %d %u\n", (int)sizeof red[0], (unsigned)red[3]);
    return 0;
}
