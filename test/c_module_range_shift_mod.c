/* included by c_module_range_shift.c: a `static` prototype first, then enough
   split typedefs to move the tokens after them, then the body last */
static int last_fn(int a);
#include <stdio.h>
typedef struct s1 { int x; } S1, *PS1;
typedef struct s2 { int x; } S2, *PS2;
typedef struct s3 { int x; } S3, *PS3;
typedef struct s4 { int x; } S4, *PS4;
typedef struct s5 { int x; } S5, *PS5;
typedef struct s6 { int x; } S6, *PS6;
typedef struct s7 { int x; } S7, *PS7;
typedef struct s8 { int x; } S8, *PS8;
typedef struct s9 { int x; } S9, *PS9;
typedef struct s10 { int x; } S10, *PS10;
static int last_fn(int a) { S1 s; PS1 p = &s; p->x = a; return p->x * 3; }
