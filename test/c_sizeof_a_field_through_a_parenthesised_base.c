/* sizeof of a RECORD FIELD reached through a base the token walk cannot start
 * from: a parenthesised expression, a cast, or a dereference.
 *
 * sizeof IS NOT A USE, so an array field does not decay -- `sizeof(x.m)` on
 * `char m[65]` is 65, whatever `x` is spelled like. pxx had two paths and only
 * one knew that: a plain identifier chain goes to CSizeofDescriptorWalk and
 * answered 65, while anything else fell through to the general-expression
 * fallback, which sized by the node's RESULT type -- and an array-typed
 * expression yields its ELEMENT type. So `(sp)->m`, `((S*)0)->m` and `(*sp).m`
 * all answered 1. A PARENTHESIS DECIDED THE ANSWER.
 *
 * ROW 4 IS THE ONE REAL CODE HITS. busybox's coreutils/uname.c declares
 *   char processor[sizeof(((struct utsname*)NULL)->machine)];
 * twice over, so the info struct came out 402 bytes instead of 530 with
 * processor, platform and os landing at CONSECUTIVE offsets. strcpy of
 * "unknown" into each then wrote through its neighbours, and `uname -p`
 * printed `uu` while `-i` printed `u` -- no diagnostic, no crash, and the
 * offsetof table was correct about the layout it had been given.
 *
 * ROWS 1, 2 AND 7 ARE THE CONTROL, not filler: they took the other path and
 * were always right, so a regression that breaks the walk instead of the
 * fallback still reddens this file. Row 8 keeps a NON-array field in view, so
 * a fix that answers "whole extent" for everything cannot pass.
 *
 * 65 IS CHOSEN SO NO ROW'S RIGHT ANSWER COLLIDES WITH A FAILURE VALUE -- not
 * 1 (the element size), not 4, not 8 (the pointer default this function seeds
 * `sz` with). A char array sized 8 would have passed while measuring nothing.
 */
#include <stdio.h>

struct S {
	int  a;
	char m[65];
	int  grid[3][4];
	char *p;
};

struct S  s;
struct S *sp = &s;

int main(void)
{
	printf("1 %d\n", (int)sizeof(s.m));                    /* walk    */
	printf("2 %d\n", (int)sizeof(sp->m));                  /* walk    */
	printf("3 %d\n", (int)sizeof((sp)->m));                /* general */
	printf("4 %d\n", (int)sizeof(((struct S*)0)->m));      /* general */
	printf("5 %d\n", (int)sizeof(((struct S*)sp)->m));     /* general */
	printf("6 %d\n", (int)sizeof((*sp).m));                /* general */
	printf("7 %d\n", (int)sizeof ((struct S*)0)->m);       /* postfix arm */
	printf("8 %d %d\n", (int)sizeof((sp)->a), (int)((sizeof((sp)->p)) == sizeof(char*)));
	printf("9 %d %d\n", (int)sizeof((*sp).grid), (int)sizeof(((struct S*)0)->grid));
	return 0;
}
