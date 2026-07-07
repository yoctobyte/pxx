/* Regression: unparenthesized `sizeof s.field` / `sizeof p->field` resolves the
   field's size, including array members. Was: only the base ident consumed, the
   `->field` dangled -> "expected C expression" (tcc tccpp.c `sizeof file->filename`). */
struct bf { int x; char filename[1024]; short tab[8]; };
int main(void){
  struct bf b; struct bf *p = &b;
  if (sizeof p->filename != 1024) return 1;
  if (sizeof b.filename  != 1024) return 2;
  if (sizeof p->tab      != 16)   return 3;   /* short[8] */
  if (sizeof b.x         != 4)    return 4;
  return 42;
}
