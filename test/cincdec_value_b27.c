/* `++`/`--` as a VALUE: postfix yields old, prefix new; works as a pointer base
   (lua's s2v(top.p++)). Exit 42. */
struct V { int val; };
int main(void) {
  int i = 5;
  int a = i++;                 /* a=5, i=6 */
  int b = ++i;                 /* b=7, i=7 */
  int j = 0;
  int second = (j++ == 0) && (j == 1);   /* postfix in expr: j++ ==0 true, j now 1 */
  struct V s[3];
  s[0].val = 3; s[1].val = 9;
  struct V *p = s;
  int c = (p++)->val;          /* c=3, p -> s[1] */
  int ok = (a==5) && (b==7) && (i==7) && second && (c==3) && (p->val==9);
  return ok ? 42 : 0;
}
