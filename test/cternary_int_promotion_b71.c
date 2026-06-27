#define EOZ (-1)
#define cast_uchar(c) ((unsigned char)(c))

int zgetc(unsigned long n, const char *p) {
  return ((n--)>0 ? cast_uchar(*(p++)) : EOZ);
}

int main(void) {
  const char *s = "A";
  if (zgetc(0, s) != -1) return 1;
  if (zgetc(1, s) != 65) return 2;
  return 42;
}
