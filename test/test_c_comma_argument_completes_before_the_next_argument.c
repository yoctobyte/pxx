/* Each call argument that contains a comma operator is evaluated COMPLETELY
 * before the next argument starts.
 *
 * The call-arg lowering emitted a comma's left operand as a statement where it
 * was lowered, and its right operand as a value read only when the call
 * gathered its arguments -- after EVERY argument's left operand. stb_ds's
 * shget, `((void) stbds_shgeti(t,k), &t[temp])->value`, stores into a shared
 * `temp`, so two shgets in one printf both printed the second key's value.
 * gcc and clang complete each argument first.
 *
 * The interesting argument sits first, last and in the middle: a scheme that
 * pins only some positions passes when the right entry happens to be first.
 * Expected is gcc's output. */
#include <stdio.h>
struct kv { char *key; int value; };
struct big { int a, b, c, d, e; };
static struct kv t[4] = {{"a",10},{"b",20},{"c",30},{"d",40}};
static struct big bg[3] = {{1,2,3,4,5},{6,7,8,9,10},{11,12,13,14,15}};
static int temp;
static int look(int k) { temp = k; return k; }
static void p3(int a, int b, int c) { printf("%d %d %d\n", a, b, c); }
static void pb(struct big x, struct big y) { printf("%d %d\n", x.a, y.e); }
#define shget(k) ((void) look(k), &t[temp])->value
#define shgetp(k) ((void) look(k), &t[temp])
int main(void) {
  p3(shget(1), shget(2), 7);
  p3(7, shget(1), shget(2));
  p3(shget(1), 7, shget(3));
  p3(*&shget(1), shgetp(2)->value, (*shgetp(3)).value);
  p3(((void) look(1), t[temp]).value, ((void) look(2), t[temp]).value, 5);
  pb(((void) look(1), bg[temp]), ((void) look(2), bg[temp]));
  printf("%s %s\n", shgetp(0)->key, shgetp(3)->key);
  printf("%g %g\n", ((void) look(1), (double)temp / 2), ((void) look(3), (double)temp / 2));
  return 0; }
