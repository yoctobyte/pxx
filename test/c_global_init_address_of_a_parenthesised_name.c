/* A file-scope pointer initialised to `&(name)` -- a parenthesised variable,
   FreeBSD's DATA_WSET/SYSINIT shape -- next to real compound literals
   `&(struct S){...}`. The `&(name)` form was read as a compound-literal type
   and broke the next function's first local declaration.
   bug-c-a-global-initialised-to-the-address-of-a-parenthesised-name-breaks-the-next-function
   Expected output is gcc's. */
#include <stdio.h>
struct S { int a, b; };
typedef struct S S_t;
struct S *s1 = &(struct S){ 3, 4 };
S_t *s2 = &(S_t){ .b = 9 };
int arr[4] = { 1, 2, 3, 4 };
int *p1 = &(arr[2]);
static void const *p2 = &(arr);
int main(void) { int n = 0; printf("%d %d %d %d %d %d\n", s1->a, s1->b, s2->b, *p1, p2 == (void *)arr, n); return 0; }
