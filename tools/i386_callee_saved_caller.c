/* Callee-saved-register oracle for a pxx i386 cdecl export.
   Used by the test-emit-obj Makefile target against
   test/test_emit_obj_386_callee_saved.pas.
   bug-a-i386-clobbers-ebx-across-a-cdecl-exported-function

   Returns the clobber mask as the EXIT STATUS: ebx=1, esi=2, edi=4, 0 = clean.
   There is deliberately NO printf on the checking path: glibc keeps the GOT
   pointer in ebx, so a probe that prints its own result cannot distinguish
   "the callee clobbered ebx" from "printf died because ebx was clobbered" --
   the original bug report was a SIGSEGV inside printf for exactly that reason.

   It also checks the RETURN VALUE, so a compiler that preserved the registers
   by breaking the function would fail here rather than pass quietly. */

int cs_probe(int, int);

int main(void) {
  int mask, value;
  value = cs_probe(1, 2);
  __asm__ volatile(
    "push %%ebx\n\t" "push %%esi\n\t" "push %%edi\n\t"
    "mov $0x11111111, %%ebx\n\t"
    "mov $0x22222222, %%esi\n\t"
    "mov $0x33333333, %%edi\n\t"
    "push $2\n\t" "push $1\n\t"
    "call cs_probe\n\t"
    "add $8, %%esp\n\t"
    "xor %%eax, %%eax\n\t"
    "cmp $0x11111111, %%ebx\n\t" "je 1f\n\t" "or $1, %%eax\n\t" "1:\n\t"
    "cmp $0x22222222, %%esi\n\t" "je 2f\n\t" "or $2, %%eax\n\t" "2:\n\t"
    "cmp $0x33333333, %%edi\n\t" "je 3f\n\t" "or $4, %%eax\n\t" "3:\n\t"
    "pop %%edi\n\t" "pop %%esi\n\t" "pop %%ebx\n\t"
    : "=a"(mask) : : "memory", "cc");
  if (value != 44096) return 8;   /* wrong answer: 8 is outside the 0..7 mask */
  return mask;
}
