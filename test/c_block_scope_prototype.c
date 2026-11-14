/* A block-scope function prototype declares the function for the calls after
 * it, when nothing at file scope does and the definition is in another
 * translation unit (test/c_block_scope_prototype_other.c). It was "call to
 * undeclared function". bug-c-a-block-scope-function-prototype-is-not-a-declaration */
#include <stdio.h>
int main(void) {
    extern int check_def(int);
    int other(void), y = 2;
    long add3(long a, long b, long c);
    printf("%d %d %ld\n", check_def(y), other(), add3(1, 20, 300));
    return 0;
}
