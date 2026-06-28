/* Global char array string literal initialization. Exit 0 on success. */
static const char a[] = "hello";
static const char b[8] = "world";

int main(void) {
  if (a[0] != 'h' || a[1] != 'e' || a[2] != 'l' || a[3] != 'l' || a[4] != 'o' || a[5] != 0) {
    return 1;
  }
  if (b[0] != 'w' || b[1] != 'o' || b[2] != 'r' || b[3] != 'l' || b[4] != 'd' || b[5] != 0 || b[6] != 0 || b[7] != 0) {
    return 2;
  }
  return 0;
}
