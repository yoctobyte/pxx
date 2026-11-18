/* ++/-- on a bitfield above bit 0 (LVGL style_cnt:6 at bit 4): prefix,
   postfix, wrap at the top of the field, signed fields, a 40-bit field.
   bug-c-increment-of-a-bitfield-above-bit-0-writes-at-bit-0 */
#include <stdio.h>
#include <stdint.h>
typedef struct { uint16_t a:1, b:3, c:6, d:1; } S;
typedef struct { int x; signed s:5; unsigned u:3; unsigned long long w:40; } T;
int main(void) {
  static S s; S *p = &s; T t = { 0, 0, 0, 0 }, *q = &t; int i, r1, r2, r3;
  p->c++; ++p->c; s.c++; p->a = 1;
  printf("%d %d %d %d\n", p->a, p->b, p->c, p->d);
  for (i = 0; i < 70; i++) r1 = p->c++;
  printf("%d %d %d\n", r1, p->c, p->a);
  r1 = p->c--; r2 = --p->c; r3 = (p->c--) + 100;
  printf("%d %d %d %d\n", r1, r2, r3, p->c);
  q->s = 15; r1 = q->s++; r2 = q->s; r3 = q->s--;
  printf("%d %d %d %d\n", r1, r2, r3, q->s);
  q->u = 7; r1 = q->u++; printf("%d %d\n", r1, q->u);
  q->w = 0xFFFFFFFFFFull; t.w++; printf("%llu %d\n", (unsigned long long)q->w, q->x);
  printf("%d\n", s.b);
  return 0;
}
