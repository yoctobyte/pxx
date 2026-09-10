/* The byte-addressable constraint classes Q and q, and the size modifiers
 * %b and %w.
 *
 * WHY THESE FOUR AND NOTHING ELSE: measured, not guessed. Across every header
 * on this box the constraint letters of this kind that occur at all are "=Q"
 * (2) and "=q" (2), and the operand modifiers are %w1 (12), %b0 (6), %w0 (5)
 * and %h0 (4). No R, no l, no %k, %q, %l or %z. `Q` and `q` are the SDL_endian
 * pair -- SDL_Swap16 is declared twice, "=q" under __i386__ (:159) and "=Q"
 * under __x86_64__ (:166) -- so a compiler supporting one letter compiles that
 * header for one of its targets and refuses it for the other, on the same
 * source. That is the same structural argument as a pointer-width {$if}
 * choosing between two routines: a family with a hole in it is not
 * half-working.
 *
 * Q is "a register whose HIGH byte is addressable" -- on x86 exactly a/b/c/d.
 * q is "a register whose LOW byte is addressable" -- all sixteen on x86-64,
 * those same four on i386. Both are honoured here as the four, which is a
 * legal narrowing of q for the same reason "g" is honoured as "r": a subset of
 * what the constraint permits is a choice the constraint allows.
 *
 * WHAT IS DELIBERATELY ABSENT: %h, the high byte. This backend cannot name it.
 * At byte width the encoder forces a REX prefix for register numbers 4..7,
 * because in its vocabulary those are spl/bpl/sil/dil -- and a REX prefix is
 * exactly what makes %ah unencodable. Emitting %h0 as (reg 4, size 1) would
 * assemble quietly to spl, a wrong REGISTER with no diagnostic. It is refused
 * by name instead and filed as an encoder gap, which is why SDL_Swap16 itself
 * still does not compile: the constraint was never its only wall.
 *
 * Expected values are gcc's on the identical source.
 * bug-c-inline-asm-constraint-q-is-unsupported-and-it-blocks-every-sdl-header
 */
#include <stdio.h>

/* "=Q" output with a "Q" input: two operands that must BOTH land in a/b/c/d,
 * so this exercises the restricted allocator rather than a single pin. */
static unsigned int qq_or(unsigned int x, unsigned int y)
{
  __asm__("orb %b1,%b0": "=Q"(x): "Q"(y), "0"(x));
  return x;
}

/* the i386 spelling of the same class, on x86-64 */
static unsigned int q_inc_low(unsigned int x)
{
  __asm__("addb $1,%b0": "=q"(x): "0"(x));
  return x;
}

/* %w on an ordinary "r": the modifier is independent of the class, and %w is
 * the most common modifier in the population above. The high half of x must
 * survive, which is what separates a 16-bit add from a 32-bit one. */
static unsigned int w_add(unsigned int x, unsigned int y)
{
  __asm__("addw %w1,%w0": "=r"(x): "r"(y), "0"(x));
  return x;
}

/* %b must not touch the upper bits either: 0xFF00 + 1 in the LOW byte is
 * 0xFF01, and a 32-bit add would give the same answer -- so the input is
 * chosen to WRAP the byte, where a 32-bit add would carry into the second
 * byte and a byte add must not. 0x12FF + 1 is 0x1200, not 0x1300. */
static unsigned int b_wrap(unsigned int x)
{
  __asm__("addb $1,%b0": "=Q"(x): "0"(x));
  return x;
}

int main(void)
{
  printf("qq_or %u\n", qq_or(0x1200u, 0x34u));
  printf("q_inc_low %u\n", q_inc_low(0xFF00u));
  printf("w_add %u\n", w_add(0x00010002u, 0x00000003u));
  printf("b_wrap %u\n", b_wrap(0x12FFu));
  return 0;
}
