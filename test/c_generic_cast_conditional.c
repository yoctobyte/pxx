/* SPDX-License-Identifier: Zlib */
/* _Generic on a pointer CAST and a pointer CONDITIONAL: the result type of
   ?: per C11 6.5.15p6 (null arm takes the other's type, a void * arm makes
   void *, qualifiers of both arms merge). systemd's const_generic() is
   `_Generic(0 ? (ptr) : (void *) 1, const void *: .., void *: ..)`.
   Row c_gencc26, against gcc. feature-c-generic-on-a-cast-or-conditional-pointer */
#include <stdio.h>

#define K(p) _Generic(0 ? (p) : (void *) 1, const void *: "const", void *: "plain", default: "OTHER")
#define T(e) _Generic((e), const char *: "cc", char *: "c", const void *: "cv", void *: "v", \
                      struct s *: "s", const struct s *: "cs", int *: "i", const int *: "ci", \
                      char **: "pp", default: "OTHER")

struct s { int x; };

int main(void)
{
    const char *a = "x";
    char *b = 0;
    const int *c = 0;
    int *d = 0;
    char *const e = 0;
    struct s sv, *sp = &sv;
    const struct s *csp = &sv;
    char **pp = 0;
    void *v = 0;
    printf("%s %s %s %s %s\n", K(a), K(b), K(c), K(d), K(e));
    printf("%s %s %s %s\n", K(sp), K(csp), K(&sv), K("lit"));
    printf("%s %s %s %s %s\n", T((void *)1), T((const void *)b), T((char *)v), T((const char *)v), T((struct s *)v));
    printf("%s %s %s %s\n", T(1 ? a : b), T(0 ? b : a), T(1 ? d : c), T(1 ? sp : csp));
    printf("%s %s %s %s\n", T(1 ? b : 0), T(0 ? 0 : a), T(1 ? b : (void *)0), T(1 ? v : a));
    printf("%s %s %s\n", T(1 ? pp : pp), T((char **)v), T(1 ? b : b));
    return 0;
}
