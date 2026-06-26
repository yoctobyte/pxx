/* gcc `__builtin_expect(x, c)` (branch-prediction hint) reduces to its first
   argument — lua uses it pervasively via l_likely/l_unlikely. Exit 5. */
#define l_likely(x)   (__builtin_expect(((x) != 0), 1))
#define l_unlikely(x) (__builtin_expect(((x) != 0), 0))
int f(int n) {
  if (l_unlikely(n < 0)) return 0;
  if (l_likely(n > 0)) return n + 2;
  return 1;
}
int main(void){ return f(3); }   /* 3+2 = 5 */
