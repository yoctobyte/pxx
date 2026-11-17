/* An array of function pointers as a struct member, spelled inline:
   `void (*fn[4])(void);`. It was laid out as ONE pointer, so the members after
   it overlapped the array and `p->fn[i]` loaded fn as a pointer and indexed
   what it pointed at (Nilix's ACPI INTx table: a page fault on q35).
   bug-c-an-array-of-function-pointers-member-is-one-pointer */
#include <stdio.h>
#include <stddef.h>
static void one(void) { printf(" 1"); }
static void two(void) { printf(" 2"); }
static int add(int a, int b) { return a + b; }
static int mul(int a, int b) { return a * b; }
struct s { unsigned gsi; void (*fn[4])(void); void *arg[4]; };
struct ops { int (*op[2])(int, int); int tag; };
union u { int (*op[3])(int, int); char c; };
static struct s tab[2];
static struct ops ops_init = { { add, mul }, 7 };
static int via(int (**q)(int, int)) { return (*q)(4, 4); }
int main(void)
{
    struct s *l = &tab[1];
    int i;
    printf("%zu %zu %zu %zu\n", sizeof(struct s), offsetof(struct s, arg),
           sizeof l->fn, sizeof l->fn[0]);
    l->fn[0] = one;
    l->fn[1] = two;
    l->arg[0] = (void *)l;
    printf("ok");
    for (i = 0; i < 4; i++)
        if (l->fn[i])
            l->fn[i]();
    (*l->fn[1])();
    printf(" %d\n", l->arg[0] == (void *)l && tab[0].fn[0] == 0);
    printf("%d %d %d\n", ops_init.op[0](3, 4), (*ops_init.op[1])(3, 4), ops_init.tag);
    printf("%zu %zu\n", sizeof(struct ops), sizeof(union u));
    {
        /* the inline pointer-to-function-pointer, `(**pp)`: its stars were
           not counted, so it was a plain function pointer and `(*pp)(a)`
           called the slot's address (bug-c-a-pointer-to-a-function-pointer-declarator-is-a-function-pointer) */
        struct ops *p = &ops_init;
        int (**pp)(int, int) = &p->op[1];
        struct { int (**at)(int, int); } h = { &ops_init.op[0] };
        printf("%d %d %d %d\n", (*pp)(5, 6), pp[0](2, 3), (*h.at)(5, 6), via(&ops_init.op[1]));
    }
    return 0;
}
