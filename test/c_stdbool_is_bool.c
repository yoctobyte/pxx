/* <stdbool.h>'s bool is _Bool, against gcc: conversion to 0/1 in casts,
 * initialisers, assignments, parameters and returns; sizeof 1; layout in a
 * struct; arrays; ++ and compound assignment on a bool.
 * bug-crtl-stdbool-defines-bool-as-int (it was `#define bool int`) */
#include <stdio.h>
#include <stdbool.h>
#include <stddef.h>

struct S { char c; bool a; bool b; short s; bool tail; };
static bool from_param(bool v) { return v; }
static bool from_ret(int v) { return v; }
static int as_int(bool v) { return v; }
static bool g = 300, garr[3] = { 4, 0, 0x100 };
static struct S gs = { 'g', 5, 2, 7, 0x200 };

int main(void) {
  volatile unsigned char m = 0x80;
  volatile long long big = 0x100000000LL;
  bool x = 256, y = big, arr[4] = { 2, 0, -1, 0x80 };
  struct S s = { 'c', 7, 0, 300, 9 };
  bool z = 0;
  int i;
  printf("sizes %d %d %d %d\n", (int)sizeof(bool), (int)sizeof(struct S), (int)offsetof(struct S, s), (int)offsetof(struct S, tail));
  printf("cast %d %d %d %d\n", (int)(bool)(m & 0x80), (bool)(m & 0x80) == (bool)1, (int)(bool)big, (int)(bool)0.5);
  printf("init %d %d", (int)x, (int)y);
  for (i = 0; i < 4; i++) printf(" %d", (int)arr[i]);
  printf("\nstruct %d %d %d %d\n", (int)s.a, (int)s.b, s.s, (int)s.tail);
  printf("call %d %d %d\n", (int)from_param(512), (int)from_ret(1024), as_int(from_param(0)));
  z = 42; printf("assign %d", (int)z);
  z += 5; printf(" %d", (int)z);
  z = 0; z++; z++; printf(" %d", (int)z);
  z = (bool)&x; printf(" %d %d %d\n", (int)z, true, false);
  z = 1; printf("incdec %d", (int)z++); printf(" %d", (int)z);
  printf(" %d", (int)++z); printf(" %d", (int)z--); printf(" %d", (int)z);
  printf(" %d", (int)z--); printf(" %d", (int)z); printf(" %d", (int)--z); printf(" %d", (int)z);
  s.a = 1; s.a++; arr[1]++; arr[1]++; printf(" %d %d\n", (int)s.a, (int)arr[1]);
  printf("static %d %d %d %d %d %d %d\n", (int)g, (int)garr[0], (int)garr[1], (int)garr[2], (int)gs.a, (int)gs.b, (int)gs.tail);
  return 0;
}
