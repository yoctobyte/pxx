/* Regression: C array element designators `[i] = v` (C 6.7.8), global + local,
   with `[]` size inference (max designated index + 1) and array-of-struct.
   Pre-fix pxx filled sequentially, ignoring `[i]=`, and sized `[]` by count.
   Returns 42. */
int a1[3]  = { [2] = 2, [0] = 0, [1] = 1 };     /* out of order */
int a2[]   = { 5, [2] = 2, 3 };                  /* size infer -> 4, hole a2[1]=0 */
struct S { int a; int b; };
struct S a3[2] = { [1] = { 3, 4 }, [0] = { 1, 2 } };

int main(void) {
    if (a1[0] != 0 || a1[1] != 1 || a1[2] != 2) return 1;
    if (sizeof(a2) != 4 * sizeof(int)) return 2;
    if (a2[0] != 5 || a2[1] != 0 || a2[2] != 2 || a2[3] != 3) return 3;
    if (a3[0].a != 1 || a3[0].b != 2) return 4;
    if (a3[1].a != 3 || a3[1].b != 4) return 5;
    return 42;
}
