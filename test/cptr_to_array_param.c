/* Regression: a function PARAMETER of pointer-to-array type `int (*q)[N]` must
   stride q[i][j] by the row size. pxx used to leave the param's row stride unset,
   so q[i][j] mis-strided (silent wrong value) — bug-c-ptr-to-array-parameter.
   Exit 42. */
static int m[3][4][5];
static int at(int (*q)[5], int i, int j){ return q[i][j]; }
static int rowsum(int (*q)[5]){ int i,j,s=0; for(i=0;i<4;i++)for(j=0;j<5;j++)s+=q[i][j]; return s; }
int main(void){
  int a,b,c;
  for(a=0;a<3;a++)for(b=0;b<4;b++)for(c=0;c<5;c++) m[a][b][c] = a*100+b*10+c;
  /* m[1] decays to int(*)[5]. */
  if (at(m[1],2,3) == 123 && at(m[0],3,4) == 34 && rowsum(m[2]) == rowsum(m[2]))
    return 42;
  return 0;
}
