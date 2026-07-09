/* b206: C pointer-to-array declarator `char (*p)[4]` (bug-c-pointer-to-array-
   declarator, c-testsuite 00130). p is a POINTER whose pointee is a fixed
   array-of-N; `p = arr` decays a 2-D array to it and `p[i][j]` flattens to
   i*N+j striding by the element size. Also exercises the sibling-declarator
   form `char arr[2][4], (*p)[4], *q;` (the multi-declarator loop used to break
   on the leading `(`). Returns 42 on success. */

int main(void) {
    char arr[2][4], (*p)[4], *q;
    int v[4], (*vp)[2], vv[3][2];

    p = arr;
    q = &arr[1][3];
    arr[0][0] = 9;
    arr[1][3] = 2;
    v[0] = 7;

    vv[0][0] = 10; vv[1][1] = 20; vv[2][0] = 30;
    vp = vv;

    if (arr[1][3] != 2) return 1;
    if (p[1][3] != 2) return 1;          /* pointer-to-array double index */
    if (p[0][0] != 9) return 1;
    if (*q != 2) return 1;               /* &arr[1][3] then deref */
    if (*v != 7) return 1;
    if (vp[1][1] != 20) return 1;        /* int element, row stride 2 */
    if (vp[2][0] != 30) return 1;
    return 42;
}
