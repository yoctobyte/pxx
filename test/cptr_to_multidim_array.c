/* Regression: a LOCAL pointer-to-multidim-array declarator `int (*p)[A][B]` and
   indexing through it. Was rejected ("expected C expression")
   (bug-c-pointer-to-multidim-array-declarator). Pairs with the partial multi-dim
   index that produces such a pointer. Exit 42. */
int gg[4][5][6][3];
int main(void){
  int a,b,c,d;
  for(a=0;a<4;a++)for(b=0;b<5;b++)for(c=0;c<6;c++)for(d=0;d<3;d++)
    gg[a][b][c][d] = a*1000+b*100+c*10+d;
  int (*p2)[6][3] = gg[2];          /* 1 of 4 partial -> int(*)[6][3] */
  int (*p3)[3]    = gg[2][4];       /* 2 of 4 partial -> int(*)[3] */
  p2[4][5][2] = 77;                 /* gg[2][4][5][2] */
  if (p2[4][5][2] == 77 && gg[2][4][5][2] == 77 &&
      p2[0][0][0] == gg[2][0][0][0] && p3[5][2] == gg[2][4][5][2])
    return 42;
  return 0;
}
