/* A struct/union tag DEFINED in a block shadows an outer tag of the same name
   until the closing brace (C11 6.2.1p4). bug-c-a-struct-tag-is-not-scoped-to-its-block.
   Expected output is gcc's. Each row names what it pins. */
#include <stdio.h>
struct G { int a; };
struct D { int a; };
enum K { KA = 1, KB };
struct D { int a; };   /* same-scope duplicate: the redefinition guard keeps the first */
int main(void) {
  struct T { int x; } s1; s1.x = 1;
  /* same tag, same members: worked before the fix and must keep working */
  { struct T { int x; } s2; s2.x = 2; printf("%d %d\n", s1.x, s2.x); }
  /* a member name the outer T lacks: was refused */
  { struct T { int y; } s3; s3.y = 2; printf("%d %d\n", s1.x, s3.y); }
  /* a member the outer T lacks, placed where the outer offset would be wrong */
  { struct T { char pad; int z; } s4; s4.pad = 9; s4.z = 3; printf("%d %d %d\n", s1.x, s4.pad, s4.z); }
  /* sizeof in the inner scope is the INNER size, and the outer one after it closes */
  { struct T { int p, q; }; printf("%d %d\n", (int)sizeof(struct T), (int)sizeof s1); }
  printf("%d\n", (int)sizeof(struct T));
  /* a file-scope tag shadowed in a block */
  { struct G { int a, b; } g; g.b = 5; printf("%d %d\n", g.b, (int)sizeof(struct G)); }
  printf("%d\n", (int)sizeof(struct G));
  /* the union spelling */
  { union U { int i; char c[8]; } u; u.i = 7; printf("%d %d\n", u.i, (int)sizeof(union U)); }
  /* the empty struct (GNU) still answers 0 and is not refused */
  { struct E { }; printf("%d\n", (int)sizeof(struct E)); }
  /* a block-local forward completed later in the same block */
  { struct N; struct N *np = 0; struct N { int k; } n; n.k = 4; np = &n; printf("%d\n", np->k); }
  /* a self-reference inside a block-local definition */
  { struct L { int v; struct L *next; } a, b; a.v = 1; a.next = &b; b.v = 2; b.next = 0; printf("%d\n", a.next->v); }
  /* a typedef spelling of the inner definition */
  { typedef struct T { double d; } TT; TT t; t.d = 1.5; printf("%g %d\n", t.d, (int)sizeof(struct T)); }
  /* the same-scope duplicate at file scope */
  { struct D d; d.a = 3; printf("%d %d\n", d.a, (int)sizeof(struct D)); }
  /* enum: an inner enum TAG shadows, and an inner ENUMERATOR shadows the outer
     one only until the brace -- the constant leaked out of the block before */
  { enum K { KC = 7, KD }; enum K y = KD; printf("%d %d\n", y, (int)sizeof(enum K)); }
  { enum Q { KA = 40 }; printf("%d\n", KA); }
  printf("%d %d\n", KA, KB);
  return 0;
}
