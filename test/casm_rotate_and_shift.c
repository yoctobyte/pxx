/* AT&T shifts and rotates in GNU inline asm: roll/rorl/rolq/rorq by %cl and
 * by an "I"/"J" immediate, plus shll/shrl/sarl/shlq. The rotate shapes are
 * libtomcrypt's ROL/ROR/ROLc/RORc/ROL64/ROR64/ROL64c/ROR64c from
 * src/headers/tomcrypt_macros.h verbatim (dropbear 2026.94 bundles it); before
 * the fix every libtomcrypt TU stopped at
 * `inline asm template has an unsupported instruction: roll`. The encoder
 * (AsmDispatch) already had all six -- only the AT&T mnemonic list lacked them.
 *
 * Values are chosen so a rotate cannot pass as a shift (bits wrap around in
 * every row) and left cannot pass as right. The expected output is gcc's.
 */
#include <stdio.h>

typedef unsigned int ulong32;
typedef unsigned long long ulong64;

static inline ulong32 ROL(ulong32 word, int i)
{
   asm ("roll %%cl,%0"
      :"=r" (word)
      :"0" (word),"c" (i));
   return word;
}

static inline ulong32 ROR(ulong32 word, int i)
{
   asm ("rorl %%cl,%0"
      :"=r" (word)
      :"0" (word),"c" (i));
   return word;
}

#define ROLc(word,i) ({ \
   ulong32 __ROLc_tmp = (word); \
   __asm__ ("roll %2, %0" : \
            "=r" (__ROLc_tmp) : \
            "0" (__ROLc_tmp), \
            "I" (i)); \
            __ROLc_tmp; \
   })
#define RORc(word,i) ({ \
   ulong32 __RORc_tmp = (word); \
   __asm__ ("rorl %2, %0" : \
            "=r" (__RORc_tmp) : \
            "0" (__RORc_tmp), \
            "I" (i)); \
            __RORc_tmp; \
   })

static inline ulong64 ROL64(ulong64 word, int i)
{
   asm("rolq %%cl,%0"
      :"=r" (word)
      :"0" (word),"c" (i));
   return word;
}

static inline ulong64 ROR64(ulong64 word, int i)
{
   asm("rorq %%cl,%0"
      :"=r" (word)
      :"0" (word),"c" (i));
   return word;
}

#define ROL64c(word,i) ({ \
   ulong64 __ROL64c_tmp = word; \
   __asm__ ("rolq %2, %0" : \
            "=r" (__ROL64c_tmp) : \
            "0" (__ROL64c_tmp), \
            "J" (i)); \
            __ROL64c_tmp; \
   })
#define ROR64c(word,i) ({ \
   ulong64 __ROR64c_tmp = word; \
   __asm__ ("rorq %2, %0" : \
            "=r" (__ROR64c_tmp) : \
            "0" (__ROR64c_tmp), \
            "J" (i)); \
            __ROR64c_tmp; \
   })

static ulong32 shifts32(ulong32 x, int n)
{
   ulong32 a = x, b = x, c = x;
   asm ("shll %%cl,%0" : "=r" (a) : "0" (a), "c" (n));
   asm ("shrl $3,%0" : "=r" (b) : "0" (b));
   asm ("sarl %%cl,%0" : "=r" (c) : "0" (c), "c" (n));
   return a ^ b ^ c;
}

static ulong64 shl64(ulong64 x)
{
   asm ("shlq $13,%0" : "=r" (x) : "0" (x));
   return x;
}

int main(void)
{
   volatile int n = 7;          /* keeps the %cl forms from folding */
   ulong32 w = 0xF0000001u;
   ulong64 q = 0xF000000000000001ull;
   printf("rol %u ror %u\n", ROL(w, n), ROR(w, n));
   printf("rolc %u rorc %u\n", ROLc(w, 8), RORc(w, 8));
   printf("rol64 %llu ror64 %llu\n", ROL64(q, n), ROR64(q, n));
   printf("rol64c %llu ror64c %llu\n", ROL64c(q, 12), ROR64c(q, 12));
   printf("shifts %u shl64 %llu\n", shifts32(0x80000F0Fu, n), shl64(q));
   return 0;
}
