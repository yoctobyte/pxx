/* b184: tcc bring-up parse batch —
   1. sizeof ((T*)0)->field (postfix chain belongs to sizeof operand)
   2. storage class AFTER type name (`T static x;`)
   3. (a, fn)(args): comma expr yields callee; left arm side effects run
   4. do..while with comma-expr condition
   5. fn-ptr + sibling declarators in one statement
   6. #undef clears ALL stacked defines of a name */
typedef struct { unsigned n_strx; unsigned short n_desc; unsigned n_value; } Sym;
typedef int TCCSem;
TCCSem static rt_sem;

#define POISON real_fn
#define POISON poison_fn
#undef POISON
int POISON(int x) { return x + 2; }   /* must stay named POISON */

int side = 0;
int f(int x) { return x + 1; }
int bump(void) { side = 7; return 0; }

int main(void)
{
    int (*fp)(int) = f, ret, *pp;
    int i = 0, n = 3;
    ret = (bump(), fp)(41);
    pp = &i;
    do { ++i; } while (++*pp, i < n);
    rt_sem = 5;
    if (sizeof ((Sym*)0)->n_desc != 2) return 1;
    if (ret != 42 || side != 7) return 2;
    if (i != 4) return 3;   /* ++*pp in the cond also bumps i */
    if (POISON(2) != 4) return 4;
    if (rt_sem != 5) return 5;
    return 42;
}
