typedef unsigned char lu_byte;

static const lu_byte classbits[] = {
  0x00,
  0x15,
  0x05,
  0x16
};

int main(void) {
  if (classbits[0] != 0x00) return 1;
  if (classbits[1] != 0x15) return 2;
  if (classbits[2] != 0x05) return 3;
  if (classbits[3] != 0x16) return 4;
  return classbits[1] + classbits[2] + classbits[3] - 6;
}
