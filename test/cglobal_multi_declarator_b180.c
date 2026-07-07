/* Regression: a global declaration with several comma-separated declarators must
   register ALL of them, including later ones with their own pointer stars
   (`static Sym *a, *b, *c;`). The loop broke on the `*` of `*b` and dropped it;
   the dropped global then folded uses to a bare 0, and `b = 0;` hit
   IRLowerAddress(int-literal) -> "Unsupported linear node" (tcc tccgen.c). */
struct Sym { int v; };
static struct Sym *a, *b, *c;
static int x, y, z;
static char *p, *q;
int main(void){
  a = 0; b = 0; c = 0;
  x = 3; y = 5; z = 7;
  static char cx = 'A', cy = 'B';
  p = &cx; q = &cy;
  if (x + y + z != 15) return 1;
  if (*p != 'A' || *q != 'B') return 2;
  if (a != 0 || b != 0 || c != 0) return 3;
  return 42;
}
