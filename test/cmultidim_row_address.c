/* Regression: `&m[i]` on a multi-dim array (address of a row) and multi-dim
   pointer-to-array function parameters. `m[i]` decays to the row address (a
   pointer-valued binop); `&` cancels the decay. Was IR_UNSUPPORTED (kind-5
   AN_BINOP) — bug-c-ptr-to-array-parameter / the &-of-row-decay interaction.
   Exit 42. */
static int m[3][4][5];
static int at3(int (*q)[4][5]){ return q[0][2][3]; }   /* multi-dim ptr param */
static int at2(int (*q)[5]){ return q[2][3]; }          /* single-dim ptr param */
int main(void){
  int a,b,c;
  for(a=0;a<3;a++)for(b=0;b<4;b++)for(c=0;c<5;c++) m[a][b][c] = a*100+b*10+c;
  int (*p)[4][5] = &m[1];          /* address of a row -> int(*)[4][5] */
  if (p[0][2][3] == 123 && at3(&m[1]) == 123 && at2(m[1]) == 123)
    return 42;
  return 0;
}
