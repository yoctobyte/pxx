/* bug-max-proc-params-32-selfmiscompile: MAX_PROC_PARAMS is 32 and a C
   function DEFINITION with 17..32 parameters compiles and computes correctly
   (the old cap silently dropped the 17th+ param; the first 32 bump crashed
   the self-hosted compiler because the builtin TProc descriptor still said
   16). gcc oracle: s=153 t=528. */
#include <stdio.h>

int sum17(int a1, int a2, int a3, int a4, int a5, int a6, int a7, int a8,
          int a9, int a10, int a11, int a12, int a13, int a14, int a15,
          int a16, int a17)
{
    return a1 + a2 + a3 + a4 + a5 + a6 + a7 + a8 + a9 + a10 + a11 + a12 +
           a13 + a14 + a15 + a16 + a17;
}

long sum32(long a1, long a2, long a3, long a4, long a5, long a6, long a7,
           long a8, long a9, long a10, long a11, long a12, long a13,
           long a14, long a15, long a16, long a17, long a18, long a19,
           long a20, long a21, long a22, long a23, long a24, long a25,
           long a26, long a27, long a28, long a29, long a30, long a31,
           long a32)
{
    long r;
    r = a1 + a2 + a3 + a4 + a5 + a6 + a7 + a8;
    r = r + a9 + a10 + a11 + a12 + a13 + a14 + a15 + a16;
    r = r + a17 + a18 + a19 + a20 + a21 + a22 + a23 + a24;
    r = r + a25 + a26 + a27 + a28 + a29 + a30 + a31 + a32;
    return r;
}

int main(void)
{
    int s = sum17(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17);
    long t = sum32(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16,
                   17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32);
    int ti = (int)t;
    printf("s=%d\n", s);
    printf("t=%d\n", ti);
    return 0;
}
