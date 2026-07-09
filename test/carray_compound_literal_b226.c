/* C99 6.5.2.5 ARRAY compound literals (elem[]){...} / (elem[N]){...}: an anonymous
   array temp that decays to a pointer to its first element. -> 42. */
static int sum3(const int *a) { return a[0] + a[1] + a[2]; }
int main(void) {
  int *p = (int[]){10, 20, 30};              /* unsized -> pointer */
  int *q = (int[4]){1, 2};                    /* sized, C99 tail-zero */
  char *s = (char[]){65, 66, 0};
  double *d = (double[]){1.5, 2.5};
  int ok = (p[1]+p[2]==50)
        && (q[0]+q[1]+q[2]+q[3]==3)
        && (sum3((int[]){12,15,15})==42)      /* as a call argument */
        && ((int[]){40,2}[0]+(int[]){40,2}[1]==42)  /* indexed directly */
        && (s[0]==65 && s[1]==66 && s[2]==0)
        && ((int)(d[0]+d[1])==4);
  return ok ? 42 : 1;
}
