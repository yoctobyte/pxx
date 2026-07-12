/* Implicit truthiness of a 64-bit value on a 32-bit target.

   A 64-bit value lives in a register PAIR on every ILP32 backend (edx:eax on i386,
   r1:r0 on arm32, a1:a0 on riscv32), but IR_JUMP_IF_FALSE tested only the LOW half:

       i386     test eax, eax
       arm32    cmp r0, #0
       riscv32  bne a0, zero

   So any nonzero value whose low 32 bits happen to be zero — 0xabcd00000000 — was
   branched on as FALSE. `if (v)`, `while (v)` and `(v) ? :` all route through that
   op, so this was silent wrong control flow, not a crash. An EXPLICIT `v != 0`
   compiled to a real 64-bit compare and was always right, which is what hid it.

   It surfaced through crtl's printf: __crtl_utoa's `while (v)` exited immediately,
   so %llx of such a value printed nothing at all (bug-32bit-truthiness-high-half).

   exit 42 = all pass. */

int main(void)
{
	unsigned long long v = 0xabcd00000000ULL;  /* nonzero; low 32 bits are ZERO */
	unsigned long long z = 0ULL;
	long long sv = (long long)0xabcd00000000LL;
	int score = 0;

	if (v == 0) return 1;                       /* full-width compare: not zero */
	if (!(v != 0)) return 2;                    /* explicit != 0 always worked */

	if (v) score += 1;                          /* implicit truthiness */
	if (sv) score += 2;                         /* signed flavour */
	score += (v) ? 4 : 0;                       /* ternary condition */

	while (v) { score += 8; break; }            /* loop condition */

	for (; v; ) { score += 16; break; }         /* for condition */

	if (!v) score += 1000;                      /* logical not must be FALSE */
	if (z) score += 1000;                       /* a real zero is still false */
	if (v && 1) score += 32;                    /* short-circuit operand */

	if (score != 63) return 3;                  /* 1+2+4+8+16+32 */
	return 42;
}
