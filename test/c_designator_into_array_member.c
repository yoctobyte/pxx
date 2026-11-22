/* Designators that index into an array member, against gcc. pxx used only
 * the LAST index (`.m2[1][2]` landed at flat 2), stored a row given as a list
 * as one scalar (`.m2[1] = {8, 9}`), and sent the values that follow a
 * designator to the next member instead of the next element (C11 6.7.9p17).
 * bug-c-a-designator-ending-in-an-index-into-a-2d-member-stores-a-list-as-one-scalar */
#include <stdio.h>

struct P { int x, y; };
struct S { int a; short m2[2][3]; int z; };
struct T { int a1[4]; char names[3][4]; struct P pts[3]; int c3[2][2][2]; int tail; };
struct D { int q; struct S d; };

static void show(const char *n, const struct S *s) {
  int i, j;
  printf("%s a=%d m2=", n, s->a);
  for (i = 0; i < 2; i++) for (j = 0; j < 3; j++) printf("%d ", s->m2[i][j]);
  printf("z=%d\n", s->z);
}

static void showt(const char *n, const struct T *t) {
  int i;
  printf("%s a1=", n);
  for (i = 0; i < 4; i++) printf("%d ", t->a1[i]);
  printf("names=[%s][%s][%s] pts=", t->names[0], t->names[1], t->names[2]);
  for (i = 0; i < 3; i++) printf("(%d,%d)", t->pts[i].x, t->pts[i].y);
  printf(" c3=");
  for (i = 0; i < 8; i++) printf("%d ", (&t->c3[0][0][0])[i]);
  printf("tail=%d\n", t->tail);
}

static struct S s1 = { .m2[1] = {8, 9} };
static struct S s2 = { .m2[0][1] = 3, 4, 5, .z = 6 };
static struct D s5 = { .d.m2[1] = {6, 7, 8}, .q = 1 };
static struct T t1 = { .a1[2] = 5, 6, .names[1] = "ab", .pts[1].y = 3, .c3[1][0] = {7, 8}, 9, 10 };

int main(void) {
  struct S g1 = { .m2[1] = {8, 9} };
  struct S g2 = { .m2[1][2] = 7, .z = 5 };
  struct S g3 = { .m2[1] = {8, 9}, 4 };
  struct S g4 = { .m2[0][1] = 3, 4, 5 };
  struct S g6 = { .m2[1][2] = 1, 2 };
  struct S g7 = { .m2[0] = 1, 2, 3, 4 };
  struct D g5 = { .d.m2[1] = {6, 7, 8}, .q = 1 };
  struct T t2 = { .a1[2] = 5, 6, .names[1] = "ab", .names[2] = {"cd"}, .pts[1] = {1, 2},
                  .pts[2].x = 4, .c3[1][1][1] = 11, .c3[0] = {{1, 2}, {3, 4}}, .tail = 12 };
  show("g1", &g1); show("g2", &g2); show("g3", &g3); show("g4", &g4);
  show("g6", &g6); show("g7", &g7);
  show("g5", &g5.d); printf("g5 q=%d\n", g5.q);
  show("s1", &s1); show("s2", &s2);
  show("s5", &s5.d); printf("s5 q=%d\n", s5.q);
  showt("t1", &t1); showt("t2", &t2);
  return 0;
}
