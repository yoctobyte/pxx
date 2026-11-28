/* SPDX-License-Identifier: Zlib */
/* _Generic over pointer-VALUED expressions that are not variables: struct
   members (pointer and array, through . and ->), call results, elements and
   dereferences that are pointers, pointer arithmetic, and the decay of const
   arrays (local, global, static, of pointers). systemd's const_generic()
   meets all of them. Row c_genpx26, against gcc.
   feature-c-generic-on-a-cast-or-conditional-pointer */
#include <stdio.h>

#define K(p) _Generic(0 ? (p) : (void *) 1, const void *: "const", void *: "plain", default: "OTHER")

struct s { char *m; const char *cm; char arr[8]; const char carr[4]; char const c2[2]; const int iarr[2]; };

static char *f(void) { return 0; } static const char *cf(void) { return 0; }
const char *a1(void) { return 0; }
char const *a4(void) { return 0; }
const char *a3(void);

const char gb[2] = { 0 };
const char *gpa[2];
const char gnb[2];

int main(void)
{
    struct s v = { 0 }, *sp = &v;
    char buf[8];
    const char cbuf[2] = { 0 };
    const char lnb[2];
    char *pa[2];
    const char *cpa[2];
    static const char sb[2];
    (void)lnb;
    printf("%s %s %s %s %s %s\n", K(v.m), K(sp->cm), K(v.arr), K(sp->carr), K(v.c2), K(sp->iarr));
    printf("%s %s %s %s %s %s\n", K(f()), K(cf()), K(a1()), K(a3()), K(a4()), K(cf() + 1));
    printf("%s %s %s %s\n", K(buf), K(cbuf), K(lnb), K(sb));
    printf("%s %s %s %s %s\n", K(pa[0]), K(cpa[1]), K(*pa), K(*cpa), K(buf + 1));
    printf("%s %s %s %s %s\n", K(gb), K(gnb), K(gpa[0]), K(*gpa), K(1 + gb));
    printf("%s %s\n", K("lit"), K((char *)cf()));
    return 0;
}

const char *a3(void) { return 0; }
