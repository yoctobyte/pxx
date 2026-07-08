/* b203: multidimensional ORDINAL global arrays read correct values
   (bug-c-multidim-ordinal-global-init). The global decl captured only the
   first dimension (rest token-skipped) so the array was mis-sized and its
   brace init dropped — `int a[2][3]={{1,2,3},{4,5,6}}` read 0. Now all dims
   are captured (SymArrNDims/DimSpan) and the init goes through the recursive
   brace-elision walker (nested + elided + partial). */

int a[2][3] = { {1, 2, 3}, {4, 5, 6} };
int elided[2][2] = { 1, 2, 3, 4 };
int d3[2][2][2] = { {{1,2},{3,4}}, {{5,6},{7,8}} };
int partial[3][2] = { {1, 2}, {3} };
int oneD[4] = { 10, 20, 30, 40 };

int main(void) {
    if (a[0][0] != 1 || a[0][2] != 3 || a[1][0] != 4 || a[1][2] != 6) return 1;
    if (sizeof(a) / sizeof(a[0][0]) != 6) return 2;
    if (elided[0][0] != 1 || elided[0][1] != 2 || elided[1][0] != 3 || elided[1][1] != 4) return 3;
    if (d3[0][0][0] != 1 || d3[1][1][1] != 8 || d3[1][0][1] != 6 || d3[0][1][0] != 3) return 4;
    if (partial[0][0] != 1 || partial[1][0] != 3 || partial[1][1] != 0 || partial[2][0] != 0) return 5;
    if (oneD[0] != 10 || oneD[3] != 40) return 6;
    return 42;
}
