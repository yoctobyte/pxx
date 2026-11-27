/* SSE2 integer instructions, `.byte`, and `call` to a local label in GNU
   inline asm, in the shapes mbedTLS's aesni.c writes when gcc builds it
   without -maes (MBEDTLS_AESNI_HAVE_CODE 1): movdqu/movdqa, movq with an
   xmm, pxor/por/pand/pandn, the immediate shifts, pshufd, the AES-NI and
   PCLMULQDQ instructions as `.byte`, and the key expansion's `call 1b`
   into a helper inside the same template. xmm clobbers. Compared with
   gcc's build: AES-128 on the FIPS-197 C.1 vector (key expansion, encrypt,
   inverse key, decrypt) and a carry-less multiply, when the CPU has AES-NI
   and PCLMULQDQ; the SSE2 rows always.
   The three AES routines are noinline, as mbedTLS's are separate functions:
   its templates advance their "r" INPUT operands (`add $16, %0`), which
   gcc tolerates only when nothing after the asm reads them.
   feature-c-inline-asm-sse-and-aes-ni */
#include <stdio.h>
#include <string.h>
#include <cpuid.h>

static void hex(const char *tag, const unsigned char *p, int n) {
  printf("%s ", tag);
  for (int i = 0; i < n; i++) printf("%02x", p[i]);
  printf("\n");
}

#define AESDEC(regs)      ".byte 0x66,0x0F,0x38,0xDE," regs "\n\t"
#define AESDECLAST(regs)  ".byte 0x66,0x0F,0x38,0xDF," regs "\n\t"
#define AESENC(regs)      ".byte 0x66,0x0F,0x38,0xDC," regs "\n\t"
#define AESENCLAST(regs)  ".byte 0x66,0x0F,0x38,0xDD," regs "\n\t"
#define AESIMC(regs)      ".byte 0x66,0x0F,0x38,0xDB," regs "\n\t"
#define AESKEYGENA(regs, imm)  ".byte 0x66,0x0F,0x3A,0xDF," regs "," imm "\n\t"
#define PCLMULQDQ(regs, imm)   ".byte 0x66,0x0F,0x3A,0x44," regs "," imm "\n\t"
#define xmm0_xmm0   "0xC0"
#define xmm0_xmm1   "0xC8"
#define xmm1_xmm0   "0xC1"

/* mbedtls_aesni_setkey_enc_128, as written there */
__attribute__((noinline)) static void setkey_128(unsigned char *rk, const unsigned char *key) {
  asm ("movdqu (%1), %%xmm0               \n\t"
       "movdqu %%xmm0, (%0)               \n\t"
       "jmp 2f                            \n\t"
       "1:                                \n\t"
       "pshufd $0xff, %%xmm1, %%xmm1      \n\t"
       "pxor %%xmm0, %%xmm1               \n\t"
       "pslldq $4, %%xmm0                 \n\t"
       "pxor %%xmm0, %%xmm1               \n\t"
       "pslldq $4, %%xmm0                 \n\t"
       "pxor %%xmm0, %%xmm1               \n\t"
       "pslldq $4, %%xmm0                 \n\t"
       "pxor %%xmm1, %%xmm0               \n\t"
       "add $16, %0                       \n\t"
       "movdqu %%xmm0, (%0)               \n\t"
       "ret                               \n\t"
       "2:                                \n\t"
       AESKEYGENA(xmm0_xmm1, "0x01")      "call 1b \n\t"
       AESKEYGENA(xmm0_xmm1, "0x02")      "call 1b \n\t"
       AESKEYGENA(xmm0_xmm1, "0x04")      "call 1b \n\t"
       AESKEYGENA(xmm0_xmm1, "0x08")      "call 1b \n\t"
       AESKEYGENA(xmm0_xmm1, "0x10")      "call 1b \n\t"
       AESKEYGENA(xmm0_xmm1, "0x20")      "call 1b \n\t"
       AESKEYGENA(xmm0_xmm1, "0x40")      "call 1b \n\t"
       AESKEYGENA(xmm0_xmm1, "0x80")      "call 1b \n\t"
       AESKEYGENA(xmm0_xmm1, "0x1B")      "call 1b \n\t"
       AESKEYGENA(xmm0_xmm1, "0x36")      "call 1b \n\t"
       :
       : "r" (rk), "r" (key)
       : "memory", "cc", "xmm0", "xmm1", "0");
}

/* mbedtls_aesni_crypt_ecb */
__attribute__((noinline)) static void crypt_ecb(const unsigned char *rk, int nr, int mode,
                      const unsigned char *in, unsigned char *out) {
  asm ("movdqu    (%3), %%xmm0    \n\t"
       "movdqu    (%1), %%xmm1    \n\t"
       "pxor      %%xmm1, %%xmm0  \n\t"
       "add       $16, %1         \n\t"
       "subl      $1, %0          \n\t"
       "test      %2, %2          \n\t"
       "jz        2f              \n\t"
       "1:                        \n\t"
       "movdqu    (%1), %%xmm1    \n\t"
       AESENC(xmm1_xmm0)
       "add       $16, %1         \n\t"
       "subl      $1, %0          \n\t"
       "jnz       1b              \n\t"
       "movdqu    (%1), %%xmm1    \n\t"
       AESENCLAST(xmm1_xmm0)
       "jmp       3f              \n\t"
       "2:                        \n\t"
       "movdqu    (%1), %%xmm1    \n\t"
       AESDEC(xmm1_xmm0)
       "add       $16, %1         \n\t"
       "subl      $1, %0          \n\t"
       "jnz       2b              \n\t"
       "movdqu    (%1), %%xmm1    \n\t"
       AESDECLAST(xmm1_xmm0)
       "3:                        \n\t"
       "movdqu    %%xmm0, (%4)    \n\t"
       :
       : "r" (nr), "r" (rk), "r" (mode), "r" (in), "r" (out)
       : "memory", "cc", "xmm0", "xmm1", "0", "1");
}

/* mbedtls_aesni_inverse_key */
__attribute__((noinline)) static void inverse_key(unsigned char *invkey, const unsigned char *fwdkey, int nr) {
  unsigned char *ik = invkey;
  const unsigned char *fk = fwdkey + 16 * nr;
  memcpy(ik, fk, 16);
  for (fk -= 16, ik += 16; fk > fwdkey; fk -= 16, ik += 16) {
    asm ("movdqu (%0), %%xmm0       \n\t"
         AESIMC(xmm0_xmm0)
         "movdqu %%xmm0, (%1)       \n\t"
         :
         : "r" (fk), "r" (ik)
         : "memory", "xmm0");
  }
  memcpy(ik, fk, 16);
}

/* the SSE2 integer forms, with a known answer (no AES-NI needed) */
static void sse2_rows(void) {
  unsigned char a[16], b[16], r[16], q[8];
  for (int i = 0; i < 16; i++) { a[i] = (unsigned char)(i * 17 + 3); b[i] = (unsigned char)(0xF0 - i * 9); }
  asm ("movdqu (%0), %%xmm2      \n\t"
       "movdqu (%1), %%xmm3      \n\t"
       "movdqa %%xmm2, %%xmm4    \n\t"
       "pxor %%xmm3, %%xmm4      \n\t"
       "por %%xmm2, %%xmm4       \n\t"
       "pand %%xmm3, %%xmm4      \n\t"
       "pandn %%xmm2, %%xmm4     \n\t"
       "movdqu %%xmm4, (%2)      \n\t"
       : : "r" (a), "r" (b), "r" (r) : "memory", "xmm2", "xmm3", "xmm4");
  hex("logic", r, 16);
  asm ("movdqu (%0), %%xmm5      \n\t"
       "psllq $3, %%xmm5         \n\t"
       "psrlq $1, %%xmm5         \n\t"
       "pslldq $3, %%xmm5        \n\t"
       "psrldq $1, %%xmm5        \n\t"
       "pshufd $0x1b, %%xmm5, %%xmm6 \n\t"
       "movdqu %%xmm6, (%1)      \n\t"
       "movq %%xmm6, (%2)        \n\t"
       "movq 8(%0), %%xmm7       \n\t"
       "movq %%xmm7, %%xmm6      \n\t"
       "movdqu %%xmm6, (%0)      \n\t"
       : : "r" (a), "r" (r), "r" (q) : "memory", "xmm5", "xmm6", "xmm7");
  hex("shift", r, 16);
  hex("movq", q, 8);
  hex("movqx", a, 16);
}

int main(void) {
  static const unsigned char key[16] = {0x00,0x01,0x02,0x03,0x04,0x05,0x06,0x07,
                                        0x08,0x09,0x0a,0x0b,0x0c,0x0d,0x0e,0x0f};
  static const unsigned char pt[16] = {0x00,0x11,0x22,0x33,0x44,0x55,0x66,0x77,
                                       0x88,0x99,0xaa,0xbb,0xcc,0xdd,0xee,0xff};
  unsigned char rk[16 * 11], ik[16 * 11], ct[16], back[16];
  unsigned int ea, eb, ec, ed;
  sse2_rows();
  if (!__get_cpuid(1, &ea, &eb, &ec, &ed) || !(ec & (1u << 25)) || !(ec & (1u << 1))) {
    printf("aes-ni: not on this CPU\n");
    return 0;
  }
  setkey_128(rk, key);
  hex("rk10", rk + 160, 16);
  crypt_ecb(rk, 10, 1, pt, ct);
  hex("enc", ct, 16);     /* FIPS-197 C.1: 69c4e0d86a7b0430d8cdb78070b4c55a */
  inverse_key(ik, rk, 10);
  crypt_ecb(ik, 10, 0, ct, back);
  hex("dec", back, 16);
  {
    unsigned char x[16], y[16], z[16];
    for (int i = 0; i < 16; i++) { x[i] = (unsigned char)(i * 29 + 1); y[i] = (unsigned char)(i * 7 + 200); }
    asm ("movdqu (%0), %%xmm0 \n\t"
         "movdqu (%1), %%xmm1 \n\t"
         PCLMULQDQ(xmm0_xmm1, "0x11")
         "movdqu %%xmm1, (%2) \n\t"
         : : "r" (x), "r" (y), "r" (z) : "memory", "xmm0", "xmm1");
    hex("clmul", z, 16);
  }
  return 0;
}
