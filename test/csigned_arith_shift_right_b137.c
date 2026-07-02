/* C signed `>>` is an arithmetic shift (sign-extends); C unsigned `>>` and
   Pascal `shr` are logical (zero-fills). All three previously collapsed onto
   the same codegen path -- CMakeBinop (cparser.inc) unconditionally remapped
   C's `>>` token onto the same `tkIdent` sentinel every backend already used
   for logical shr, so a negative signed value shifted in zeros instead of
   the sign bit (bug-c-signed-arith-shift-right). Fixed by keeping a signed
   C `>>` on the (previously unused past parse time) `tkShr` token instead,
   and adding a genuine arithmetic-shift case to every backend's codegen
   (each verified byte-for-byte against a real cross-assembler before
   landing). */

int main(void) {
  int s = -2;
  if ((s >> 1) != -1) return 1;

  int t = -8;
  if ((t >> 2) != -2) return 2;

  /* variable (register, not immediate) shift count */
  int n = 1;
  if ((s >> n) != -1) return 3;

  /* unsigned >> must stay logical (unaffected by this fix) */
  unsigned int u = 0xFFFFFFFEu;
  if ((u >> 1) != 2147483647u) return 4;

  /* a positive signed value: arithmetic and logical shift agree, so this
     alone wouldn't have caught a regression, but it should still hold */
  int p = 8;
  if ((p >> 2) != 2) return 5;

  return 42;
}
