struct Pair {
  int a;
  int b;
};

int main(int argc, char **argv) {
  char *words[2] = {"ab", "xyz"};
  char **pp = words;
  int x = 41;
  int *p1 = &x;
  int **p2 = &p1;
  int ***p3 = &p2;
  struct Pair s;
  struct Pair *sp1 = &s;
  struct Pair **sp2 = &sp1;

  if (argc < 3) return 1;

  if (argv[1][0] != 'a') return 2;
  if (argv[1][1] != 'b') return 3;
  if (argv[2][0] != 'x') return 4;
  if (argv[2][2] != 'z') return 5;

  if (pp[0][1] != 'b') return 6;
  if (pp[1][2] != 'z') return 7;

  ***p3 = ***p3 + 1;
  if (x != 42) return 8;
  if (***p3 != 42) return 9;

  (**sp2).a = 11;
  (*sp1).b = 31;
  if ((**sp2).a + (**sp2).b != 42) return 10;

  return 42;
}
