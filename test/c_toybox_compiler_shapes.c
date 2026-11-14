/* Compiler shapes toybox 0.8.15 hit (feature-c-toybox-builds-with-pxx). Expected
   output is gcc's.
   1. A string literal in a file-scope constant expression is a non-null
      address: `"opts" || 0` is 1 (toybox's NEED_OPTIONS folded to 0 and no
      command parsed its options).
   2. main's frame holds main's locals, not the file-scope initialisers'
      temporaries: toybox measures recursion from &argc and gave up past 24 KB.
   3. Indexing a pointer-to-pointer struct member keeps the last level:
      `*s.m[i]` is a char (toybox's `*toys.optargs[1]` read four bytes).
   4. typeof of an arithmetic expression and of a type name. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const int NEED = 0 || "opts" || 0;
static const int NOTSTR = !"x";
int ORED = "q" && 1;

/* enough initialised file-scope data to have inflated main's frame */
struct ent { const char *name; int (*fn)(int); const char *opts; unsigned flags; };
static int f1(int x) { return x + 1; }
struct ent table[] = {
  {"a", f1, "ab", 1}, {"b", f1, 0, 2}, {"c", f1, "c:", 3}, {"d", f1, "d", 4},
  {"e", f1, "e#", 5}, {"f", f1, 0, 6}, {"g", f1, "g", 7}, {"h", f1, "h", 8},
};
char *names[] = {"x", "y", "z", "w", "v", "u", "t", "s"};

static long *top;
static long depth(void) { long here; return labs((long)top - (long)&here); }

struct ctx { int x; char **optargs; int **ip; double **dd; unsigned char **ub; } g;

int main(int argc, char **argv)
{
  char *a[] = {"0x8", "1abc"}; int v[] = {7, 8}; int *ia[] = {v, v};
  double dv[] = {1.5, 2.5}; double *dp[] = {dv};
  unsigned char ubv[] = {200, 201}; unsigned char *ubp[] = {ubv};
  struct ctx l, *p = &g;
  long long big = 5000000000LL; unsigned short us = 65535;

  (void)argc; (void)argv;
  top = (long *)&argc;
  printf("const %d %d %d\n", NEED, NOTSTR, ORED);
  printf("main frame small %d\n", depth() < 4096);
  printf("table %s %d %s\n", table[2].name, table[7].fn(table[7].flags), names[5]);

  g.optargs = a; g.ip = ia; g.dd = dp; g.ub = ubp; l = g;
  printf("ptrptr %d %d %d %d %d\n", *g.optargs[1], g.optargs[1][1], **g.optargs,
         *l.optargs[1], *p->optargs[0]);
  printf("ptrptr2 %d %d %g %g %d %d\n", *g.ip[1], g.ip[1][1], *g.dd[0], p->dd[0][1],
         *p->ub[0], p->ub[0][1]);
  printf("sizes %d %d\n", (int)sizeof(*g.optargs[1]), (int)sizeof(**g.ip));

  {
    __typeof__(big) b2 = big - 1;
    typeof(us) u2 = us;
    typeof(int) i2 = 3;
    typeof(1.5 * 2) d2 = 2.5;
    u2++;
    printf("typeof %lld %d %d %g %d\n", (long long)b2, (int)u2, i2, d2,
           (int)sizeof(typeof(big)));
  }
  return 0;
}
