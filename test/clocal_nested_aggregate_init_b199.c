/* b199: LOCAL aggregate initializers via the recursive brace-elision walker
   (bug-c-local-nested-aggregate-init). Previously the local decl path used a
   one-level field/element loop that DROPPED nested-aggregate members (a nested
   struct field, a struct element's sub-array), so these read garbage; a
   typedef-array element even errored. The global walker (b193) now also drives
   local decls in an AST-chain emit mode. */

struct P { int x, y; };
struct Box { struct P tl, br; };
struct S2 { int a, b; union { int c; int d; }; };
typedef struct { int v; int sub[2]; } WithSub;

int main(void) {
    struct Box box = { 1, 2, 3, 4 };            /* full brace elision, nested struct */
    if (box.tl.x != 1 || box.tl.y != 2 || box.br.x != 3 || box.br.y != 4) return 1;

    struct S2 v = { 1, 2, 3 };                  /* anonymous union member */
    if (v.a != 1 || v.b != 2 || v.c != 3 || v.d != 3) return 2;

    WithSub a[1] = { { 1, { 2, 3 } } };         /* array-of-struct with sub-array */
    if (a[0].v != 1 || a[0].sub[0] != 2 || a[0].sub[1] != 3) return 3;

    struct P pa[2] = { { 10, 20 }, { 30, 40 } };/* array of struct */
    if (pa[0].x != 10 || pa[1].y != 40) return 4;

    int m[2][3] = { { 1, 2, 3 }, { 4, 5, 6 } }; /* explicit multidim ordinal */
    if (m[0][0] != 1 || m[1][2] != 6) return 5;

    struct Box z = { 0 };                        /* partial: tail zero-filled */
    if (z.tl.x != 0 || z.br.y != 0) return 6;

    return 42;
}
