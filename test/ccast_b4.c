/* Slice B increment 2c fixture: sizeof and casts. Exit code asserted vs gcc. */
struct P { int x; int y; double z; };
int main(void) {
  int r = 0;
  r += sizeof(int) + sizeof(char) + sizeof(long); /* 4+1+8 = 13 */
  r += sizeof(struct P);                          /* 16 -> 29 */
  int a[10];
  r += sizeof(a) / sizeof(int);                   /* 40/4 = 10 -> 39 */
  long n = 7;
  r += (int)n * 3;                                /* 21 -> 60 */
  int x = 42;
  void *vp = &x;
  int *ip = (int *)vp;
  r += *ip;                                       /* 42 -> 102 */
  return r;                                        /* 102 */
}
