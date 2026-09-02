/* A function RETURNING a function pointer, `RET (*name(params))(args)`, across
 * the parameter counts that actually discriminate.
 *
 * Row 1 is the shape that KEPT WORKING while every other row was refused:
 * `void (*look(void))(void)`. A test written only around it would have been
 * green throughout the outage, which is the whole reason it is row 1 and
 * labelled -- a zero-parameter case cannot stand in for the family.
 *
 * The declaration takes the fnRetIsFunc arm of ParseCSubroutine, which parses
 * no parameter list of its own. `paramsOverflow` was initialised in the OTHER
 * arm only and read after both, so this shape read it off the stack and the
 * compiler answered "more than 16 parameters not supported" for a function
 * with one. Nothing assigns that variable on this path, so a True there could
 * only ever have come from uninitialised storage.
 * bug-c-a-function-returning-a-function-pointer-is-refused-as-having-16-parameters
 *
 * Rows 5 and 6 call THROUGH the returned pointer with arguments, so the second
 * signature -- the `(args)` group, not the `(params)` one -- has to be right
 * too; a fix that recovered only the outer parameter count would pass rows 1-4
 * and get these wrong.
 */
#include <stdio.h>

static void plain(void)        { printf("2 plain\n"); }
static int  addone(int x)      { return x + 1; }
static int  mul(int a, int b)  { return a * b; }

static void (*look0(void))(void)            { return plain; }
static void (*look1(int a))(void)           { (void)a; return plain; }
static void (*look2(int a, int b))(void)    { (void)a; (void)b; return plain; }

/* forward declaration first, definition after -- two passes over the same
   declarator, and the forward form alone was never refused */
static int (*pick(int which))(int);
static int (*pick(int which))(int)          { return which ? addone : addone; }

static int (*pick2(int a, int b))(int, int) { (void)a; (void)b; return mul; }

int main(void)
{
  printf("1 %d\n", look0() == plain);
  look1(7)();                                  /* prints row 2 */
  printf("3 %d\n", look2(1, 2) == plain);
  printf("4 %d\n", pick(1) == addone);
  printf("5 %d\n", pick(0)(41));
  printf("6 %d\n", pick2(9, 9)(6, 7));
  return 0;
}
