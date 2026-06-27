static double gd = 3.14;
static float gf = -1.5;

int main(void) {
  long dbits = *(long *)&gd;
  int fbits = *(int *)&gf;

  if (((dbits >> 56) & 0xff) != 0x40) return 1;
  if (((fbits >> 24) & 0xff) != 0xbf) return 2;
  return 42;
}
