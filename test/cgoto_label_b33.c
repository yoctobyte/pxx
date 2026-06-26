/* goto + labels (lua's match() uses `goto init`). Forward and backward. Exit 42. */
int sum_to(int n) {
  int s = 0;
again:
  if (n <= 0) goto done;
  s += n; n--;
  goto again;
done:
  return s;
}
int main(void) {
  int i = 0, c = 0;
loop:
  i++; c += 2;
  if (i < 3) goto loop;        /* c = 6 */
  return sum_to(8) + c;        /* 36 + 6 = 42 */
}
