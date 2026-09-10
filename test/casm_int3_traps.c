/* `int $3` — SDL_assert.h's SDL_TriggerBreakpoint.
 *
 * THE ASSERTION IS THE TRAP, AND THE FIRST INSTRUMENT I REACHED FOR WAS WRONG.
 * The obvious check is to count CC bytes in the binary against the same
 * program without the asm. Measured: both binaries came out at EXACTLY 120216
 * bytes with EXACTLY 75 CC bytes each — and one of them traps while the other
 * exits cleanly. A whole-binary byte count has no instruction framing, CC is
 * also the padding filler, and the code region shifted without changing the
 * total. It reported "nothing was emitted" about a working instruction.
 *
 * So the row asserts the only thing that cannot be produced by accident: the
 * process dies of SIGTRAP. gcc on identical source does the same, which is the
 * differential half. The Makefile row inverts the usual sense deliberately —
 * a ZERO exit here is the failure.
 *
 * CC rather than CD 03 is the encoding CHOICE, measured against `as`, which
 * assembles `int $3` to exactly cc. It carries NO standing byte assertion and
 * this comment is the only record of it: int is emitted from asmenc.inc via
 * AsmB, and neither standalone .inc harness includes that file, so there is
 * nowhere in the suite that can currently see the byte. Both encodings raise
 * vector 3, so the SIGTRAP below cannot tell them apart either. If that
 * distinction ever matters, the harness has to reach asmenc.inc first.
 */
int f(int x)
{
  __asm__ __volatile__ ( "int $3\n\t" );
  return x;
}

int main(void)
{
  return f(0);
}
