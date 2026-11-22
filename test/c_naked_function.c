/* __attribute__((naked)) and asm branches to C functions, against gcc.
 * micropython's py/nlrx64.c: nlr_push is naked -- no prologue, so (%rsp) is
 * the return address -- stores the callee-saved registers into a buffer and
 * `jmp`s to a C tail that returns for it. pxx ignored naked (the asm ran
 * under a pushed rbp) and refused `jmp name`.
 * feature-c-attribute-naked-and-inline-asm-branches-to-symbols */
#include <stdio.h>

typedef struct { long pad[2]; long rip, rbp, rsp, rbx, r12, r13, r14, r15; } buf_t;

unsigned int save_tail(buf_t *b);
unsigned int ext_tail(buf_t *b);   /* defined after use: the branch is resolved at the end */
static long seen_ret;

__attribute__((naked)) unsigned int save(buf_t *b) {
  __asm volatile (
    "movq   (%rsp), %rax   \n"
    "movq   %rax, 16(%rdi) \n"
    "movq   %rbp, 24(%rdi) \n"
    "movq   %rsp, 32(%rdi) \n"
    "movq   %rbx, 40(%rdi) \n"
    "movq   %r12, 48(%rdi) \n"
    "movq   %r13, 56(%rdi) \n"
    "movq   %r14, 64(%rdi) \n"
    "movq   %r15, 72(%rdi) \n"
    "jmp    save_tail      \n"
  );
}

/* a naked body with a local label, a call, and its own ret */
__attribute__((naked)) long twice_plus(long x) {
  __asm volatile ("movq %rdi, %rax\n"
                  "addq %rax, %rax\n"
                  "testq %rax, %rax\n"
                  "jns 1f\n"
                  "negq %rax\n"
                  "1:\n");
  __asm volatile ("pushq %rax\n"
                  "call ext_tail\n"
                  "popq %rax\n"
                  "addq $1, %rax\n"
                  "ret\n");
}

unsigned int save_tail(buf_t *b) {
  seen_ret = b->rip;
  return (unsigned int)(b->rsp & 7) + 40;
}

unsigned int ext_tail(buf_t *b) { (void)b; return 0; }

__attribute__((noinline)) static int probe(buf_t *b) {
  unsigned int r = save(b);
  return (int)r;
}

int main(void) {
  buf_t b = {{0}};
  int r = probe(&b);
  printf("save returned %d\n", r);
  printf("rip saved %d, inside probe's caller code %d\n", b.rip != 0, seen_ret == b.rip);
  printf("rsp slot 8-aligned at entry %d\n", (b.rsp & 15) == 8);
  printf("twice_plus %ld %ld %ld\n", twice_plus(5), twice_plus(-7), twice_plus(0));
  return 0;
}
