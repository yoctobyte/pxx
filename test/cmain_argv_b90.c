int main(int argc, char **argv) {
  char *a;
  char *b;

  if (argc < 3) return 1;

  a = argv[1];
  b = argv[2];

  if (a[0] != 'a') return 2;
  if (a[1] != 'b') return 3;
  if (a[2] != 0) return 4;

  if (b[0] != 'x') return 5;
  if (b[1] != 'y') return 6;
  if (b[2] != 'z') return 7;
  if (b[3] != 0) return 8;

  return 42;
}
