static int set7(int a, int b, int c, int *p, int elem, int limit, const char *what) {
  if (a != 11) return 1;
  if (b != 22) return 2;
  if (c != 33) return 3;
  if (elem != 55) return 4;
  if (limit != 66) return 5;
  if (what[0] != 'x') return 6;
  *p = 42;
  return *p;
}

int main(void) {
  int size = 0;
  int got = set7(11, 22, 33, &size, 55, 66, "x");
  if (got != 42) return got;
  return size;
}
