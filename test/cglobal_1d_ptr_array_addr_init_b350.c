/* A 1-D GLOBAL pointer array whose initializer holds an element the flat
   pre-scan cannot fold — `&g`, `(void*)0`, `&arr[i][j]`, a cast — used to be
   zero-skipped WHOLE: every element (including foldable ones) silently read
   back nil, and dereferencing died. csmith seed 2's
   `static const int32_t *g_474[2] = {&g_79,&g_79};` is exactly this shape
   (bug-c-csmith-seed2-segfault, b350). The initializer now defers to the
   recursive walker. Mixed foldable elements (strings, bare array names, NULL)
   must keep working through the same path. */
#include <stdio.h>

static int g_79 = 7;
static int g_two[2][3] = {{1, 2, 3}, {4, 5, 6}};
static char buf[4] = "hi";

/* the csmith shape: all elements address-of a scalar global */
static const int *g_474[2] = {&g_79, &g_79};
/* mixed: (void*)0 holes between address-of elements (csmith g_259) */
static int *holes[4] = {(void *)0, &g_79, (void *)0, &g_79};
/* address of a multidim element + NULL + bare array name (decay) + string */
static char *mix[3] = {(void *)0, buf, "zz"};
static int *deep[2] = {&g_two[1][2], &g_two[0][1]};
/* unsized: length must come from the deferred initializer */
static int *unsized[] = {&g_79, (void *)0, &g_79};
/* volatile double-pointer chain, read back through two derefs */
static const int **const volatile g_488 = &g_474[0];

int main(void) {
  printf("g474=%d %d\n", *g_474[0], *g_474[1]);
  printf("holes=%d %d %d %d\n", holes[0] ? *holes[0] : -1,
         holes[1] ? *holes[1] : -1, holes[2] ? *holes[2] : -1,
         holes[3] ? *holes[3] : -1);
  printf("mix=%s %s %s\n", mix[0] ? mix[0] : "null", mix[1], mix[2]);
  printf("deep=%d %d\n", *deep[0], *deep[1]);
  printf("unsized=%d %d %d n=%d\n", unsized[0] ? *unsized[0] : -1,
         unsized[1] ? *unsized[1] : -1, unsized[2] ? *unsized[2] : -1,
         (int)(sizeof(unsized) / sizeof(unsized[0])));
  printf("dblderef=%d\n", **g_488);
  return 0;
}
