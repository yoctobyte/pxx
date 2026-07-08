/* b194: sizeof(arr->field) on an ARRAY-of-struct symbol — the element record
   lives in ElemRecName (RecName is unset for arrays), so `cases->c` sized as
   a pointer (8) instead of the array field (4*sizeof(long) = 32), collapsing
   c-testsuite 00205's inner print loop to one iteration. */

typedef long I;
typedef struct { I c[4]; I b, e, k; } PT;
PT cases[] = { 1, 2, 3, 4, 5, 6, 7 };

int main() {
    if (sizeof(cases->c) != 4 * sizeof(I)) return 1;
    if (sizeof(cases->c) / sizeof(cases->c[0]) != 4) return 2;
    if (sizeof(cases[0]) != sizeof(PT)) return 3;
    return 42;
}
