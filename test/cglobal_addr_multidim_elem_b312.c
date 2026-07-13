/* A global pointer initialised to the address of a MULTIDIM array element.

       static int a3[4][6][9];
       static int *p = &a3[3][4][2];

   The initializer parser consumed exactly ONE `[...]`. The leftover `[` then failed the
   comma/semicolon check that follows, so the whole initializer was SKIPPED -- silently.
   The pointer stayed null, and the first store through it segfaulted.

   `&a[5]` on a 1-D array always worked, which is why no corpus caught it. csmith emits
   these constantly (`static int32_t ** volatile g_62 = &g_63[3][4][2];`).

   The offset is the row-major flat index: flat := flat * span[d] + i[d]. */
int printf(const char *, ...);

static int a3[4][6][9];
static int a2[5][7];
static int a1[10];
static int *p3 = &a3[3][4][2];
static int *p2 = &a2[2][3];
static int *p1 = &a1[5];
static int *p0 = &a1[0];

int main(void)
{
    a3[3][4][2] = 77;
    a2[2][3]    = 66;
    a1[5]       = 55;
    a1[0]       = 44;

    /* the VALUE reached through each pointer, and the OFFSET it actually points at */
    printf("3d=%d off=%d want=%d\n", *p3, (int)(p3 - &a3[0][0][0]), 3*6*9 + 4*9 + 2);
    printf("2d=%d off=%d want=%d\n", *p2, (int)(p2 - &a2[0][0]),    2*7 + 3);
    printf("1d=%d off=%d want=%d\n", *p1, (int)(p1 - &a1[0]),       5);
    printf("0 =%d off=%d want=%d\n", *p0, (int)(p0 - &a1[0]),       0);

    /* and a store THROUGH the pointer must land in the array */
    *p3 = 11; *p2 = 22;
    printf("stored=%d %d\n", a3[3][4][2], a2[2][3]);
    return 0;
}
