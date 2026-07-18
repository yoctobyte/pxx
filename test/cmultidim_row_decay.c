/* Regression: single-subscript row decay of a multi-dim array. g[i] on a >=2-D
   array is the C decay to a pointer to the remaining sub-array; pxx used to
   mis-decay it to a scalar load (NULL) and SIGSEGV
   (bug-c-multidim-single-subscript-row-decay). Cover 2-D int*, 3-D int(*)[N],
   and passing a row to a pointer parameter. Exit 42. */
static int g2[6][4];
static int g3[2][6][4];
static int sum4(int *r){ int s=0,i; for(i=0;i<4;i++) s+=r[i]; return s; }
int main(void){
  int i,j;
  for(i=0;i<6;i++) for(j=0;j<4;j++) g2[i][j] = i*4+j;
  for(i=0;i<2;i++){int a,b;for(a=0;a<6;a++)for(b=0;b<4;b++)g3[i][a][b]=i*100+a*10+b;}
  int *r2 = g2[3];              /* 2-D row decay */
  int (*r3)[4] = g3[1];        /* 3-D row decay */
  if (r2[2] == 14 && sum4(g2[1]) == (4+5+6+7) &&
      r3[3][2] == 132 && g3[1][3][2] == 132)
    return 42;
  return 0;
}
