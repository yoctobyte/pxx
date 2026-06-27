int classify(const char *fmt) {
  switch (*(fmt + 1)) {
    case 's': return 40;
    case 'd': return 20;
    default: return *(fmt + 1);
  }
}

int read_direct(const char *p) {
  return *(p + 2);
}

int main(void) {
  int a = classify("%s:%d");
  int b = read_direct("abcd");
  return (a == 40 && b == 'c') ? 42 : 1;
}
