#include <stdio.h>
struct proc;
extern void (*pv)(struct proc *); extern void (*pf)(void); extern int (*pd)(void *); extern void *pc;
int nullop(void *v) { return 0; }
int main(void) { printf("%d %d %d %d\n", (void*)pv == (void*)nullop, (void*)pf == (void*)nullop, (void*)pd == (void*)nullop, pc == (void*)nullop); return 0; }
