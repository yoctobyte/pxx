/* pxx --link, like ld --gc-sections, needs no definition for a name that
 * only a DROPPED section refers to: `dead` is never reached from main, so its
 * section is collected and its call to the undefined `nowhere` is never
 * relocated. With --no-gc-sections `dead` is kept and the link must refuse,
 * as ld does without --gc-sections. rump's objects carry ~50 such names, all
 * from header `static inline` copies nothing calls. Compiled with
 * --function-sections so `dead` has a section of its own. */
#include <stdio.h>
void nowhere(void);
void dead(void) { nowhere(); }
int main(void) { printf("kept\n"); return 0; }
