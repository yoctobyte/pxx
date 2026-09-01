/* THE PXX HALF of the only gate in this family with an outside opinion about
   AGGREGATES. Compiled by pxx to an object; linked by gcc against
   c_abi_mixed_link_main.c, which gcc compiles. Neither half can be swapped for
   a pxx-compiled caller: a pxx-vs-pxx pair agrees with itself whatever the
   convention, which is why every other subject here was green while
   bug-a-c-a-by-value-struct-parameter-is-passed-as-a-pointer-to-every-c-abi-callee
   segfaulted on contact with gcc.

   BOTH DIRECTIONS, because they fail independently: `take_*` is a pxx CALLEE
   reading what gcc laid down, `relay_*` is a pxx CALLER laying down what a gcc
   callee reads. A convention bug in one direction is invisible from the other.

   The shapes are chosen against the SysV x86-64 classification boundaries --
   1 eightbyte / 2 eightbytes / MEMORY past 16 bytes / all-SSE / mixed
   INTEGER+SSE -- and against i386 cdecl, where every aggregate is stack bytes
   and the discriminator is padding and order instead. Fields are weighted so
   any permutation, truncation or pointer-instead-of-value changes the answer. */

struct P2  { int a, b; };                        /* 8  : 1 eightbyte, INTEGER */
struct P4  { int a, b, c, d; };                  /* 16 : 2 eightbytes, INTEGER */
struct P6  { int a, b, c, d, e, f; };            /* 24 : MEMORY */
struct D2  { double x, y; };                     /* 16 : 2 eightbytes, SSE */
struct MIX { int a; double y; };                 /* 16 : INTEGER + SSE */
struct C3  { char a, b, c; };                    /* 3  : sub-word */

int    take_p2 (struct P2 p)  { return p.a * 10 + p.b; }
int    take_p4 (struct P4 p)  { return ((p.a * 10 + p.b) * 10 + p.c) * 10 + p.d; }
int    take_p6 (struct P6 p)  { return p.a*1 + p.b*2 + p.c*3 + p.d*4 + p.e*5 + p.f*6; }
double take_d2 (struct D2 p)  { return p.x * 10.0 + p.y; }
double take_mix(struct MIX p) { return p.a * 100.0 + p.y; }
int    take_c3 (struct C3 p)  { return p.a * 100 + p.b * 10 + p.c; }

/* A struct arriving AFTER the integer bank is nearly full: on SysV the
   classification interacts with how many registers are already spoken for. */
int take_late(int a, int b, int c, int d, int e, struct P2 p)
{ return ((((a*10+b)*10+c)*10+d)*10+e) * 100 + p.a * 10 + p.b; }

/* pxx as the CALLER. gcc compiles the callees; we hand them the aggregates. */
extern int    gcc_p2 (struct P2 p);
extern int    gcc_p4 (struct P4 p);
extern int    gcc_p6 (struct P6 p);
extern double gcc_d2 (struct D2 p);
extern double gcc_mix(struct MIX p);
extern int    gcc_late(int a, int b, int c, int d, int e, struct P2 p);

int    relay_p2 (int a, int b) { struct P2 p; p.a=a; p.b=b; return gcc_p2(p); }
int    relay_p4 (void) { struct P4 p; p.a=1;p.b=2;p.c=3;p.d=4; return gcc_p4(p); }
int    relay_p6 (void) { struct P6 p; p.a=1;p.b=2;p.c=3;p.d=4;p.e=5;p.f=6; return gcc_p6(p); }
double relay_d2 (void) { struct D2 p; p.x=1.5; p.y=2.5; return gcc_d2(p); }
double relay_mix(void) { struct MIX p; p.a=7; p.y=0.25; return gcc_mix(p); }
int    relay_late(void) { struct P2 p; p.a=8; p.b=9; return gcc_late(1,2,3,4,5,p); }

/* THROUGH A FUNCTION POINTER, which is a SECOND caller in this compiler and not
   a variation on the first: the direct and indirect cdecl arms classify
   arguments in separate loops, and the aggregate work landed in the direct one
   while the gate stayed green -- because every relay above is a direct call, so
   the subject could not contain the defect. Both classes are here (INTEGER, and
   INTEGER+SSE) because the indirect arm counts the two banks independently too.
   bug-a-c-a-by-value-struct-parameter-is-passed-as-a-pointer-to-every-c-abi-callee */
typedef int    (*fn_p2)(struct P2);
typedef double (*fn_mix)(struct MIX);

int    relay_p2_ind (void) { struct P2  p; fn_p2  f = gcc_p2;  p.a=3; p.b=7;    return f(p); }
double relay_mix_ind(void) { struct MIX p; fn_mix f = gcc_mix; p.a=7; p.y=0.25; return f(p); }
