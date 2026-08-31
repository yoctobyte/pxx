/* AAPCS32 stack arguments and variadic tail, measured against GLIBC.
   dprintf is not implemented by crtl, so this resolves to the armel sysroot's
   libc and glibc decides what the bytes mean. No pxx-side convention can
   flatter the answer -- which is the substitute for the arm32 gcc this box
   does not have. */
extern int dprintf(int fd, const char *fmt, ...);
int main(void) {
  /* 2 named words + 6 int words = 8: four arguments past r0..r3. */
  dprintf(1, "ints %d %d %d %d %d %d\n", 11, 22, 33, 44, 55, 66);
  /* A double in the tail gets an even word index under AAPCS. */
  dprintf(1, "mixed %d %.2f %d\n", 7, 2.5, 9);
  /* Two doubles plus enough ints to push the second one onto the stack. */
  dprintf(1, "wide %d %.2f %d %.2f %d\n", 1, 1.5, 2, 2.5, 3);
  return 0;
}
