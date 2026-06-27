/* `*(long*)&d` must load the pointed-at 8-byte width, not int (4). Before the
   CNodePointeeTk AN_PTR_CAST fix this read only the low 32 bits of the double. */
int main(void) {
  double d = 2.5;                 /* 0x4004000000000000 */
  long b = *(long *)&d;
  double e = *(double *)&b;
  return (e == 2.5 && (b >> 32) != 0) ? 42 : 1;
}
