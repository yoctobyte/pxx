/* Regression: file-scope function-pointer TYPEDEF arrays `fptr t[N] = {a,b}`
   (and unsized `fp t[] = {&sq,&dbl}`). The fn-ptr global path only recognised
   INLINE declarators `(*t[N])()`; a typedef array left the trailing [N] after the
   name unconsumed (desync) and wasArr false. Now the [N] is parsed and `&func`
   element prefixes accepted. gcc-verified. feature-c-compound-literals piece 3. */
typedef void (*vfn)(void);
typedef int  (*ifn)(int);
static int g;
static void a(void){ g += 1; }
static void b(void){ g += 2; }
static void c(void){ g += 4; }
static int  sq(int x){ return x * x; }
static int  dbl(int x){ return x + x; }

const vfn vt[3] = { a, b, c };
ifn it[] = { &sq, &dbl };

int main(void) {
  int i, ok = 1;
  for (i = 0; i < 3; i++) vt[i]();
  if (g != 7) ok = 0;
  if (!(it[0](5) == 25 && it[1](5) == 10)) ok = 0;
  if ((int)(sizeof(it)/sizeof(it[0])) != 2) ok = 0;
  return ok ? 42 : 1;
}
