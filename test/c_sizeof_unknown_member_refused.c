/* A sizeof operand naming a member the struct does not have is refused, as a
 * read or a store of it is. It compiled to 4. Five spellings, five refusals;
 * gcc refuses each.
 * bug-c-an-unknown-member-name-compiles-as-int */
#include <stdio.h>
struct s { int a; char b; double d[3]; struct s *next; } x, *px = &x;
int main(void) {
    printf("%zu\n", sizeof(x.zz));
    printf("%zu\n", sizeof x.yy);
    printf("%zu\n", sizeof(px->ww));
    printf("%zu\n", sizeof (*px->vv));
    printf("%zu\n", sizeof ((struct s *)0)->uu);
    printf("%zu %zu\n", sizeof(x.d), sizeof px->next->b);   /* fine */
    return 0;
}
