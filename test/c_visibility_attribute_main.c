/* main for c_visibility_attribute.c: the hidden symbols are still
   reachable inside the link, and plain() calls them. */
#include <stdio.h>
int plain(void);
extern int pvar;
int main(void) { printf("%d %d\n", plain(), pvar); return 0; }
