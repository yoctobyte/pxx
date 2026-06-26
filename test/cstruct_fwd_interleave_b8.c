/* A forward struct typedef whose body is laid out AFTER another struct's fields
   were added in between. The forward record's field base must re-anchor at body
   layout, else field lookup (and fn-ptr field calls) miss the fields. This is the
   lua ZIO / Mbuffer pattern. Exit code 42. */
typedef int (*BinOp)(int, int);

typedef struct Zio ZIO;                 /* forward: record created here */
typedef struct Mb { int a; int b; int c; } Mb;   /* fields added in between */
struct Zio { int n; BinOp reader; int x; };       /* body laid out later */

int mul(int a, int b) { return a * b; }

int call(ZIO *z) { return z->reader(6, 7); }   /* field lookup must find `reader` */

int main(void) {
  struct Zio z;
  z.n = 1;
  z.reader = mul;
  z.x = 2;
  return call(&z);   /* 6 * 7 = 42 */
}
