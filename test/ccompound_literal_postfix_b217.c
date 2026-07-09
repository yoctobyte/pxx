/* Postfix on a compound literal: (T){...}.field / ->  (gap A).
   The CL node routes through ParseCPostfixTail so `.f` chains onto it. -> 42. */
struct P { int a; int b; int c; };
int main(void) {
  int r = 0;
  r += (struct P){7,9,0}.b;               /* 9 */
  r += (struct P){10,20,30}.c;            /* +30 = 39 */
  struct P *pp = &(struct P){1,2,3};
  r += pp->b;                             /* +2 = 41 */
  r += (struct P){0,1,0}.b;               /* +1 = 42 */
  return r;
}
