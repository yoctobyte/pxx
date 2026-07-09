/* b205: multidimensional FLOAT/DOUBLE global arrays read correct values
   (bug-c-multidim-float-brace-init). The multidim global brace-init path was
   gated TypeIsOrdinal, so `float m[2][4]={{..},{..}}` fell through to the skip
   path and read 0.0 (the flat-FLOAT path is 1-D only). The gate now admits
   float element types too, routing through the recursive brace-elision walker
   whose leaf store handles floats — same as the already-fixed LOCAL case. */

float gm[2][4] = { {1, 2, 3, 4}, {5, 6, 7, 8} };
double gd[2][3] = { {1.5, 2.5, 3.5}, {4.5, 5.5, 6.5} };
double elided[2][2] = { 1.5, 2.5, 3.5, 4.5 };
float partial[3][2] = { {1.5, 2.5}, {3.5} };

typedef float vec4[4];
vec4 rows[2] = { {1, 2, 3, 4}, {5, 6, 7, 8} };

static int feq(double a, double b) { double d = a - b; if (d < 0) d = -d; return d < 1e-9; }

int main(void) {
    if (!feq(gm[0][0], 1) || !feq(gm[0][3], 4) || !feq(gm[1][0], 5) || !feq(gm[1][3], 8)) return 1;
    if (!feq(gd[0][0], 1.5) || !feq(gd[0][2], 3.5) || !feq(gd[1][0], 4.5) || !feq(gd[1][2], 6.5)) return 2;
    if (!feq(elided[0][0], 1.5) || !feq(elided[1][1], 4.5)) return 3;
    if (!feq(partial[0][0], 1.5) || !feq(partial[1][0], 3.5) || !feq(partial[1][1], 0) || !feq(partial[2][0], 0)) return 4;
    if (!feq(rows[0][0], 1) || !feq(rows[1][3], 8)) return 5;
    return 42;
}
