/* C array-syntax function parameters `T name[]` / `T name[N]` decay to pointers
   (lua ltable computesizes(unsigned int nums[], ...)). Before, they parsed as a
   non-pointer and indexing gave wrong values. Exit 42. */
int sum(int a[], int n) {
  int s = 0, i;
  for (i = 0; i < n; i++) s += a[i];
  return s;
}
unsigned int third(unsigned int v[5]) { return v[2]; }
int main(void) {
  int x[3]; x[0] = 18; x[1] = 6; x[2] = 9;          /* sum 33 */
  unsigned int y[5]; y[2] = 9;
  return sum(x, 3) + third(y);                        /* 33 + 9 = 42 */
}
