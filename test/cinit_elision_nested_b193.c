/* b193: recursive global aggregate initializer walker (C99 6.7.8) —
   brace elision, nested subaggregates, anonymous unions, designators,
   fn-pointer / string / &global fields, unsized array sizing under elision.
   (c-testsuite 00050 / 00091 / 00205 family) */

int f1(int x) { return x + 1; }
int f2(int x) { return x * 2; }
int gv = 7;

struct S1 { int a; int b; };
struct S2 {
    int a;
    int b;
    union { int c; int d; };
    struct S1 s;
};
struct S2 v = {1, 2, 3, {4, 5}};          /* anon union + nested braces */

typedef struct { int v; int sub[2]; } S;
S sa[1] = {{1, {2, 3}}};                  /* nested braces, array-of-struct */

typedef long I;
typedef struct { I c[4]; I b, e, k; } PT;
PT cases[] = {                            /* fully elided flat lists */
    1, 2, 3, 4, 5, 6, 7,
    8, 9, 10, 11, 12, 13, 14,
};

struct Ops { int tag; int (*fn)(int); const char *name; int *ptr; };
struct Ops table[] = {
    { 1, f1, "one", &gv },
    { 2, f2, "two", 0 },
};

struct Cfg { int a; int b; char lbl[8]; } cfg = { .b = 5, .a = 3, .lbl = "cf" };

struct Pt { int x, y; };
struct Box { struct Pt tl, br; } box = { 1, 2, 3, 4 };   /* full elision */

int strcmp(const char *, const char *);

int main() {
    if (v.a != 1 || v.b != 2) return 1;
    if (v.c != 3 || v.d != 3) return 2;   /* union: both views read 3 */
    if (v.s.a != 4 || v.s.b != 5) return 3;
    if (sa[0].v != 1 || sa[0].sub[0] != 2 || sa[0].sub[1] != 3) return 4;
    if (sizeof(cases) / sizeof(cases[0]) != 2) return 5;   /* 14 leaves / 7 = 2 */
    if (cases[0].c[3] != 4 || cases[0].k != 7) return 6;
    if (cases[1].c[0] != 8 || cases[1].b != 12 || cases[1].e != 13 || cases[1].k != 14) return 7;
    if (table[0].tag != 1 || table[0].fn(10) != 11) return 8;
    if (table[1].fn(10) != 20) return 9;
    if (strcmp(table[0].name, "one")) return 10;
    if (*table[0].ptr != 7 || table[1].ptr != 0) return 11;
    if (cfg.a != 3 || cfg.b != 5 || strcmp(cfg.lbl, "cf")) return 12;
    if (box.tl.x != 1 || box.tl.y != 2 || box.br.x != 3 || box.br.y != 4) return 13;
    return 42;
}
