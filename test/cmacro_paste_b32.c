/* `##` token-paste operator. `DBL_ ## n` -> DBL_<n>, then re-scanned/expanded
   (lua's l_mathlim DBL_##MANT_DIG). Exit 42. */
#define CAT(a, b) a ## b
#define PFX(p)    VAL_ ## p
#define VAL_MANT  42
int main(void) {
  int z = CAT(1, 7);          /* 17 */
  int m = PFX(MANT);          /* VAL_MANT = 42 */
  return (z == 17) ? m : 0;
}
