/* `(type)` cast inside a constant expression (lua ltable
   `nums[MAXABITS + 1]`, MAXABITS = cast_int(...) = ((int)(...))). Exit 42. */
#define cast_int(i) ((int)(i))
enum { E = (int)7 };
int main(void) {
  int a[(int)(2 * 4 - 1) + 1];     /* size 8 */
  int b[cast_int(3)];              /* size 3 */
  a[7] = 20; b[2] = 22;
  return a[7] + b[2] + (E - 7);    /* 20 + 22 + 0 = 42 */
}
