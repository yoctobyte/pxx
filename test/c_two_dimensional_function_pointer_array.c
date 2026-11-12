/* A two-dimensional array of function pointers, both spellings, both scopes:
   `void (*h[16][4])(void)` (Gibux irq.c, 2026-11-13) and `fptr h[3][2]`.
   Each `[` in the declarator used to overwrite the last dimension, so h was a
   1-D array of 4 and h[11][0] = f wrote past its end (SIGSEGV); the typedef
   spelling at file scope was a parse error at the call. Output is gcc's. */
#include <stdio.h>
#define PER_IRQ 4
typedef void (*handler_t)(void);

static void a(void) { puts("a"); }
static void b(void) { puts("b"); }

static void (*handlers[16][PER_IRQ])(void);
static handler_t th[3][2];

int main(void)
{
    int irq = 11;
    handlers[irq][0] = a; handlers[irq][1] = b; handlers[3][0] = b;
    for (int i = 0; i < PER_IRQ && handlers[irq][i]; i++)
        handlers[irq][i]();
    handlers[3][0]();
    printf("%d %d\n", (int)sizeof handlers, handlers[2][0] == 0);

    void (*loc[2][3])(void) = {0};
    loc[1][2] = a; loc[1][2]();
    printf("%d\n", (int)sizeof loc);

    th[1][0] = a; th[1][1] = b; th[2][1] = a;
    for (int i = 0; i < 2 && th[1][i]; i++)
        th[1][i]();
    th[2][1]();
    handler_t tl[2][2] = {{0}};
    tl[1][1] = b; tl[1][1]();
    printf("%d %d\n", (int)sizeof th, (int)sizeof tl);
    return 0;
}
