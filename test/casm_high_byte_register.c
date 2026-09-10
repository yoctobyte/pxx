/* %ah / %ch / %dh / %bh — the high-byte registers, via the %h operand
 * modifier and the Q constraint class.
 *
 * WHY THIS NEEDED AN ENCODER CHANGE RATHER THAN A FRONTEND ONE. The high-byte
 * registers are numbers 4..7 at byte width with NO REX prefix. The SAME four
 * numbers at the SAME width WITH a REX prefix are spl/bpl/sil/dil. The number
 * alone cannot say which is meant, and EncPrefixAndREX resolved that ambiguity
 * the only way it could before this existed: at size 1 it FORCES a REX for
 * 4..7. So `%h0` had no representation at all, and emitting it as (reg 4,
 * size 1) assembled quietly to spl.
 *
 * THE VALUE ROWS ARE THE CONTROL, AND THEY ARE VIOLENT ONES. If a REX prefix
 * were emitted here, `xchg %ah,%al` (86 e0) would become `xchg %spl,%al`
 * (40 86 e0) — swapping the low byte of the STACK POINTER with al. That does
 * not return a wrong number, it destroys the frame. So these rows cannot pass
 * with the bug present: there is no encoding of them that is quietly wrong.
 * sethigh IS THAT ROW AND IT ALREADY EARNED ITS PLACE. The first version of
 * this fix suppressed REX one layer too high, in AsmPrefixAndREX, and
 * `movb $0x7F,%h0` reached x64_mov_reg_imm instead — which calls
 * EncPrefixAndREX directly, as 58 of its 60 call sites do. The emitted bytes
 * were `40 b5 7f`: `mov $0x7f,%bpl`, the low byte of the frame pointer. It
 * segfaulted, which is how the missing sibling path was found. swap16 and
 * highbyte both PASSED at that moment — one arm of the family fixed, one not,
 * and only the row using a different opcode could tell.
 *
 * A byte-level delta against the same program with the asm stripped confirms
 * the REX+B0..B7 class (the one that bug lived in) goes from 4 to 4, delta
 * zero. That check does not generalise further: over a whole binary a scan
 * for `40..4f` followed by a byte opcode has no instruction framing and sits
 * at ~846 either way, so it cannot see two instructions. The VALUE rows are
 * the framed instrument, and they are violent ones — every register a wrong
 * REX would select (spl/bpl/sil/dil) is the low byte of rsp, rbp, rsi or rdi.
 *
 * Expected values are gcc's on identical source. swap16 is SDL_endian.h's
 * SDL_Swap16 verbatim, which is why the family exists at all.
 * bug-a-the-x86-64-encoder-cannot-name-a-high-byte-register
 */
#include <stdio.h>

/* SDL_endian.h:166, verbatim */
static unsigned short swap16(unsigned short x)
{
  __asm__("xchgb %b0,%h0": "=Q"(x):"0"(x));
  return x;
}

/* read the high byte out rather than swapping, so the row fails differently
 * from swap16 if the modifier selects the wrong half */
static unsigned int highbyte(unsigned int x)
{
  unsigned int r;
  __asm__("movb %h1,%b0": "=Q"(r): "Q"(x));
  return r & 0xFFu;
}

/* write INTO the high byte: the destination half, which the two rows above
 * only ever read */
static unsigned int sethigh(unsigned int x)
{
  __asm__("movb $0x7F,%h0": "=Q"(x): "0"(x));
  return x;
}

/* two live Q operands at once, so the restricted allocator has to place them
 * in two DIFFERENT registers of a/b/c/d and both must keep a valid high half */
static unsigned int addhigh(unsigned int a, unsigned int b)
{
  __asm__("addb %h1,%h0": "=Q"(a): "Q"(b), "0"(a));
  return a;
}

int main(void)
{
  printf("swap16 %u\n", (unsigned)swap16(0x1234));
  printf("highbyte %u\n", highbyte(0xAB12u));
  printf("sethigh %u\n", sethigh(0x0034u));
  printf("addhigh %u\n", addhigh(0x0500u, 0x0300u));
  return 0;
}
