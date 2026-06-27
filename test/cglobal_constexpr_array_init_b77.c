/* Global ordinal array initialized with a brace list of constant EXPRESSIONS
   (parens, shifts, bitwise-or, and enum/macro constants), not plain int
   literals. The flat-int-init gate previously rejected any element containing
   `(`/identifier and silently zero-initialized the whole array — this is lua's
   `const lu_byte luaP_opmodes[] = { opmode(...), ... }` (each element expands to
   `(((mm)<<7)|...|(iABC))`). With the table zeroed, `testTMode`/`getOpMode`
   returned 0 for every opcode, so lua's `getjumpcontrol` mis-identified jump
   control instructions and `negatecondition`'s SETARG_k corrupted JMPs ->
   if/else, while, for crashed. */

extern long __pxx_write(int, const void *, unsigned long);

typedef unsigned char lu_byte;
enum Mode { mA, mB, mC, mD };
#define opmode(t, a, m) (((t) << 4) | ((a) << 3) | (m))

static const lu_byte tab[6] = {
  opmode(0, 1, mA),          /*  0|8|0  = 8  */
  opmode(1, 1, mB),          /* 16|8|1  = 25 */
  opmode(0, 0, mC),          /*  0|0|2  = 2  */
  opmode(1, 0, mD),          /* 16|0|3  = 19 */
  42,                        /* plain literal still works */
  (1 << 4) | 3               /* bare const expr = 19 */
};

#define testT(m) (tab[m] & (1 << 4))

int main(void) {
  if (tab[0] != 8)  return 1;
  if (tab[1] != 25) return 2;
  if (tab[2] != 2)  return 3;
  if (tab[3] != 19) return 4;
  if (tab[4] != 42) return 5;
  if (tab[5] != 19) return 6;
  /* the predicate lua relies on: bit 4 set iff t==1 */
  if (testT(0))  return 7;     /* t=0 -> clear */
  if (!testT(1)) return 8;     /* t=1 -> set   */
  return 42;
}
