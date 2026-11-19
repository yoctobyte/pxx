/* -fstack-protector-strong: WHICH functions are protected, gcc's strong rule.
   Protected: a local array (arr), one in an inner block (nested), an
   address-taken local (addr), a member's address (saddr), a struct holding an
   array (sarr). Not: pointer indexing (ptr), scalars only (scal). The row
   lists the functions whose code references __stack_chk_guard.
   feature-c-stack-protector-strong-global-guard */
struct S { int n; char name[8]; };
struct T { int a, b; };
void use(void *);
int arr(int i) { char b[32]; b[i] = 1; return b[0]; }
int nested(int i) { if (i) { char b[4]; b[0] = (char)i; return b[0]; } return 0; }
int addr(int i) { int x = i; use(&x); return x; }
int saddr(void) { struct T t; t.a = 1; use(&t.b); return t.a; }
int sarr(void) { struct S s; s.n = 1; return s.n; }
int ptr(int *p) { return p[3] + *p; }
int scal(int a) { int b = a + 1; return b * 2; }
