/* bswapl / bswapq / pause / int $3 — the rest of what SDL2's headers ask the
 * x86-64 inline assembler for.
 *
 * WHY THIS SET AND NOT A LONGER ONE. Censused from SDL2's own headers rather
 * than discovered one compile at a time: grepping __asm__ across every header in /usr/include/SDL2
 * names twelve mnemonics, and nine are behind architecture guards this target
 * never takes (rlwimi is ppc, dmb/mcr/bkpt are arm and aarch64, ebreak is
 * riscv). What x86-64 actually reaches is xchgb+%h0 — already landed — plus
 * exactly these. A first-failure walk would have found them one rebuild at a
 * time and could not have said when it was finished; the census says the
 * surface is closed.
 *
 * WHAT EACH ROW CAN SEE, which is the part a value alone does not say.
 *
 * The bswap ENCODINGS are asserted byte-for-byte in test/test_x64enc.pas —
 * four rows over REX.W and REX.B independently, against `as`. This file is the
 * value-and-oracle half.
 *
 * bswap32/bswap64 are chosen so that the right answer differs from the input
 * in every byte, and so that the two widths cannot pass each other's
 * assertion: a 64-bit swap of the 32-bit value would put the significant
 * bytes at the top and answer 0, and a 32-bit swap of the 64-bit one truncates.
 * So neither row can be satisfied by the other's encoding, which is the
 * failure a missing REX.W would actually produce.
 *
 * bswap_r8plus exists because the register rides IN the opcode (0F C8+rd)
 * rather than in a ModRM byte, so the high-register bit is REX.B and nothing
 * downstream would notice it missing — the instruction would still assemble
 * and would swap the WRONG register. Verified against `as`: bswap %r15d is
 * 41 0f cf where bswap %edi is 0f cf, one prefix apart and a different
 * register entirely.
 *
 * MEASURED, AND IT CORRECTS WHAT THIS ROW WAS WRITTEN TO DO. The intent was to
 * force the operand up into r8..r15, on the assumption that the plain rows sit
 * in a/b/c/d. Scanning the emitted bytes says pxx's allocator puts EVERY one of
 * these in r8 already — 41 0f c8 twice and 49 0f c8 once — so REX.B is
 * exercised by all three rows and this one adds no coverage over them under
 * pxx. It is kept because it does under GCC, where the same source picks %edx
 * (0f ca / 48 0f ca, no REX at all), so the file's two compilers between them
 * cover both sides of the prefix. Do not read this row as the REX.B control;
 * the control is that pxx and gcc AGREE on the value while emitting different
 * registers.
 *
 * AND objdump CANNOT DISASSEMBLE A PXX BINARY — `objdump -d` parses zero
 * instructions out of one. Checking these rows that way reports "no bswap
 * present" for a binary that contains three, which reads exactly like the
 * feature being absent. Scan for the byte pattern, or trust the value rows.
 *
 * pause has NO observable value by construction: it is a hint, and a plain nop
 * is a legal implementation of it. So this row asserts what it CAN — that the
 * loop terminates with the right count — and NOT the prefix. Dropping the F3
 * leaves a correct-looking nop and this file still prints the same four lines.
 *
 * The prefix is covered by the Makefile row instead, as a paired byte delta:
 * F3 90 goes 0 -> 1 between this program and the same loop without the asm.
 * That pairing is the whole instrument — bare 90 moves 261 -> 265 over the
 * same two binaries and is pure noise, which is what a count with no framing
 * looks like. The row itself then demonstrated the same failure a second time:
 * written with `tr -d` the hex runs together, so 'f390' matched ACROSS two
 * adjacent bytes and the CONTROL binary answered 2 where the truth is 0.
 * Byte boundaries have to survive into the search or the search is about a
 * different question. It is NOT in test/test_x64enc.pas: pause is emitted from
 * asmenc.inc via AsmB, and neither standalone harness includes that file.
 *
 * int $3 is NOT in this file. It cannot be: executing it traps, and compiling
 * it into a function nothing calls proves only that it parsed. It has its own
 * row, test/casm_int3_traps.c, whose assertion is the SIGTRAP itself — see the
 * note there about why a byte count was the wrong instrument for it.
 *
 * Expected values are gcc's on identical source.
 */
#include <stdio.h>

/* SDL_endian.h's SDL_Swap32, verbatim shape */
static unsigned int bswap32(unsigned int x)
{
  __asm__("bswapl %0": "=r"(x):"0"(x));
  return x;
}

/* SDL_endian.h's SDL_Swap64 for the __x86_64__ arm */
static unsigned long long bswap64(unsigned long long x)
{
  __asm__("bswapq %0": "=r"(x):"0"(x));
  return x;
}

/* Enough simultaneously-live values that the "=r" operand cannot be placed in
 * a/b/c/d/si/di — it has to land in r8..r15, where the encoding needs REX.B
 * and would otherwise swap a different register silently. */
static unsigned int bswap_r8plus(unsigned int a, unsigned int b, unsigned int c,
                                 unsigned int d, unsigned int e, unsigned int f)
{
  unsigned int t = a;
  __asm__("bswapl %0": "=r"(t): "0"(t));
  return t ^ (b + c + d + e + f);
}

/* pause: no value to assert — see the header. The count is what this row can
 * actually observe. */
static unsigned int spin(unsigned int n)
{
  unsigned int i, k = 0;
  for (i = 0; i < n; i++) { __asm__ __volatile__("pause\n"); k++; }
  return k;
}

int main(void)
{
  printf("bswap32 %u\n", bswap32(0x12345678u));
  printf("bswap64 %llu\n", bswap64(0x0123456789ABCDEFull));
  printf("bswap_r8plus %u\n", bswap_r8plus(0x11223344u, 1, 2, 3, 4, 5));
  printf("spin %u\n", spin(7));
  return 0;
}
