/* A typedef of a pointer-to-pointer (`typedef struct D **PPD;`) as a variable,
   a cast, a parameter, a struct member, a sibling declarator, under extra
   stars, and through a second typedef. Every form must reach the struct's
   SECOND field; the bug read offset 0 or a stray word.
   bug-c-pointer-to-pointer-struct-member-reads-offset-0 */
#include <stdio.h>

struct D { int v; int w; };
typedef struct D **PPD;
typedef struct D *PD;
typedef PD *PPD2;              /* the same type spelled through a one-level typedef */
typedef PPD PPD3;              /* an alias of the two-level typedef */
typedef int **PPI;
typedef PPD *PPPD;             /* three levels */
typedef char *str;             /* a one-level typedef under a further star */

struct Holder { int pad; PPD pp; str *sp; };

static int via_param(PPD p) { return p[0]->w + (*p)->v; }
static int via_param3(PPPD p) { return (**p)->w; }

int main(void)
{
  struct D d = {40, 2};
  struct D *pd = &d;
  void *pp = &pd;
  int i7 = 7, *ip = &i7;
  PPD q = (PPD)pp;
  PPD2 q2 = &pd;
  PPD3 q3 = q;
  PPD s1 = q, s2 = q, *s3 = &q;       /* siblings, one with an extra star */
  PPPD t = &q;
  PPI pi = &ip;
  struct Holder h;
  h.pad = 0; h.pp = q;

  printf("var    %d %d %d\n", q[0]->w, (*q)->w, q[0][0].w);
  printf("alias  %d %d %d\n", q2[0]->w, q3[0]->w, (*q3)->v);
  printf("sibs   %d %d %d\n", s1[0]->w, s2[0]->w, (*s3)[0]->w);
  printf("three  %d %d\n", t[0][0]->w, (**t)->v);
  printf("cast   %d %d\n", ((PPD)pp)[0]->w, (*(PPD)pp)->w);
  printf("rawcst %d %d\n", ((struct D **)pp)[0]->w, (*(struct D **)pp)->w);
  printf("param  %d %d\n", via_param(q), via_param3(&q));
  printf("member %d %d\n", h.pp[0]->w, (*h.pp)->v);
  printf("int    %d %d\n", pi[0][0], **pi);
  printf("sizeof %d %d %d\n", (int)sizeof(PPD), (int)sizeof(*q), (int)sizeof(**q));
  printf("step   %d\n", (int)((char *)(q + 1) - (char *)q));
  {
    /* no typedef at all: index-then-arrow three levels down */
    struct D **q0 = &pd, ***z = &q0;
    printf("plain3 %d %d %d %d\n", z[0][0]->w, (**z)->w, (*z)[0]->w, z[0][0][0].w);
    printf("cast3  %d %d\n", ((struct D ***)&q0)[0][0]->w, (*(struct D ***)&q0)[0]->w);
  }
  {
    /* bug-c-a-pointer-typedef-loses-its-base-under-indexing: a byte, not 4 */
    char buf[] = "ABCD", *b = buf;
    str *c = &b;
    h.sp = &b;
    printf("str    %d %d %d %d\n", *c[0], c[0][1], *h.sp[0], h.sp[0][1]);
  }
  return 0;
}
