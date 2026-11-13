/* `__attribute__((mode(TI)))` asks for a 128-bit integer, and pxx has none.
 * It used to be skipped like any other attribute, so this typedef silently
 * became a 64-bit type: libtommath's mp_word under MP_64BIT (its default for
 * any __GNUC__ x86-64 compiler), where every digit product lost its high half
 * and dropbear's RSA key generation looped forever looking for a prime.
 * It must now be REFUSED, naming the attribute. The narrower modes and an
 * identifier that merely contains "mode" must still compile; the Makefile
 * row checks both halves with -dMODE_TI_ROW off and on.
 */
typedef unsigned int u8m __attribute__((mode(QI)));
typedef int wordm __attribute__((__mode__(__word__)));
int nomode_counter;

#ifdef MODE_TI_ROW
typedef unsigned long private_mp_word __attribute__((mode(TI)));
#endif

int main(void)
{
  return nomode_counter;
}
