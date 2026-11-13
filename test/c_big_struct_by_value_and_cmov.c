/* Two things dropbear 2026.94's post-quantum key exchange needed, against gcc.
 *
 * 1. A struct of more than 1 KiB passed BY VALUE. libcrux_mlkem768_sha3.h
 *    passes libcrux_ml_kem_types_MlKemPrivateKey_55 (uint8_t value[2400]) by
 *    value. SysV puts it on the stack (MEMORY class), 300 eightbytes, and pxx
 *    counted one ABI slot per eightbyte against a cap of 128: "C call: too
 *    many argument slots". It is now one slot whose push loop copies all of
 *    it. The rows pass it directly, through a function pointer (the second
 *    call site of the same rule), and between register arguments on both
 *    sides, and read bytes at the start, the middle and the very end, so a
 *    short copy or a shifted one shows.
 *
 * 2. cmov<cc> with a w suffix, sntrup761.c's constant-time compares
 *    verbatim. The encoder had cmovcc; the AT&T mnemonic list did not.
 *
 * The expected output is gcc's.
 */
#include <stdio.h>
#include <stdint.h>
#include <string.h>

typedef struct { uint8_t value[2400]; } PrivKey;
typedef struct { uint8_t value[1184]; } PubKey;
typedef struct { PrivKey sk; PubKey pk; } KeyPair;

static unsigned sum(PrivKey k)
{
  unsigned s = 0;
  int i;
  for (i = 0; i < 2400; i++) s = s * 31 + k.value[i];
  return s;
}

static unsigned mixed(int a, PrivKey k, long b, PubKey p, int c)
{
  return (unsigned)a * 7 + k.value[0] + k.value[1199] + k.value[2399]
       + (unsigned)b * 3 + p.value[0] + p.value[1183] + (unsigned)c;
}

/* By value in, by value out: libcrux's from_17_35(sk, pk) shape. */
static KeyPair make_pair(PrivKey sk, PubKey pk)
{
  KeyPair r;
  r.sk = sk;
  r.pk = pk;
  return r;
}

typedef int16_t crypto_int16;

static crypto_int16 crypto_int16_nonzero_mask(crypto_int16 crypto_int16_x)
{
  crypto_int16 crypto_int16_q, crypto_int16_z;
  __asm__ ("xorw %0,%0\n movw $-1,%1\n testw %2,%2\n cmovnew %1,%0" : "=&r"(crypto_int16_z), "=&r"(crypto_int16_q) : "r"(crypto_int16_x) : "cc");
  return crypto_int16_z;
}

static crypto_int16 crypto_int16_positive_01(crypto_int16 crypto_int16_x)
{
  crypto_int16 crypto_int16_q, crypto_int16_z;
  __asm__ ("xorw %0,%0\n movw $1,%1\n testw %2,%2\n cmovgw %1,%0" : "=&r"(crypto_int16_z), "=&r"(crypto_int16_q) : "r"(crypto_int16_x) : "cc");
  return crypto_int16_z;
}

static crypto_int16 crypto_int16_equal_mask(crypto_int16 crypto_int16_x, crypto_int16 crypto_int16_y)
{
  crypto_int16 crypto_int16_q, crypto_int16_z;
  __asm__ ("xorw %0,%0\n movw $-1,%1\n cmpw %3,%2\n cmovew %1,%0" : "=&r"(crypto_int16_z), "=&r"(crypto_int16_q) : "r"(crypto_int16_x), "r"(crypto_int16_y) : "cc");
  return crypto_int16_z;
}

static long cmov64(long a, long b, long c)
{
  long r = a;
  __asm__ ("cmpq %2,%3\n cmovlq %1,%0" : "+r"(r) : "r"(b), "r"(c), "r"(a) : "cc");
  return r;
}

int main(void)
{
  static PrivKey k;
  static PubKey p;
  static KeyPair kp;
  unsigned (*fp)(int, PrivKey, long, PubKey, int) = mixed;
  int i;

  for (i = 0; i < 2400; i++) k.value[i] = (uint8_t)(i * 7 + 3);
  for (i = 0; i < 1184; i++) p.value[i] = (uint8_t)(i * 5 + 1);
  printf("sum %u\n", sum(k));
  printf("mixed %u\n", mixed(11, k, 22, p, 33));
  printf("fnptr %u\n", fp(11, k, 22, p, 33));
  kp = make_pair(k, p);
  printf("pair %d %d %d %d\n", memcmp(&kp.sk, &k, sizeof k), memcmp(&kp.pk, &p, sizeof p),
         kp.sk.value[2399], kp.pk.value[1183]);

  printf("nonzero %d %d\n", crypto_int16_nonzero_mask(0), crypto_int16_nonzero_mask(-3));
  printf("positive %d %d %d\n", crypto_int16_positive_01(5), crypto_int16_positive_01(0),
         crypto_int16_positive_01(-5));
  printf("equal %d %d\n", crypto_int16_equal_mask(4, 4), crypto_int16_equal_mask(4, 5));
  printf("cmov64 %ld %ld\n", cmov64(1, 2, 3), cmov64(1, 2, 0));
  return 0;
}
