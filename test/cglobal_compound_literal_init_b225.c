/* File-scope struct var initialized by a compound literal: `= (T){...}` or
   `= ((T){...})` (00216 gs). The wrapper parens/cast are stripped so the deferred
   record brace-init runs; static storage == the braced init on the var. -> 42. */
struct S { int a, b, c, d; };
struct S gs  = ((struct S){1, 2, 3, 4});
struct S gs2 = (struct S){5, 6, 7, 8};
struct S g1  = (struct S){9, 10}, g2 = {11, 12};   /* multi-declarator, mixed */
int main(void) {
  return (gs.a==1 && gs.d==4 && gs2.a==5 && gs2.d==8
          && g1.a==9 && g1.b==10 && g2.a==11 && g2.b==12) ? 42 : 1;
}
