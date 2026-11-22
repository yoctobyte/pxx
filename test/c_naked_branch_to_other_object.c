/* __attribute__((naked)) whose asm branches to a function in ANOTHER object
 * (`jmp`/`call` through the GOT slot), against gcc. micropython nlrx64.c:
 * nlr_push_tail may live in another unit. Pairs with
 * c_naked_branch_to_other_object_tail.c.
 * feature-c-attribute-naked-and-inline-asm-branches-to-symbols */
#include <stdio.h>
typedef struct { long rip, rsp; } buf_t;
unsigned int tail_elsewhere(buf_t *b);
__attribute__((naked)) unsigned int grab(buf_t *b) {
  __asm volatile ("movq (%rsp), %rax\n movq %rax, (%rdi)\n movq %rsp, 8(%rdi)\n jmp tail_elsewhere\n");
}
__attribute__((naked)) unsigned int grab_call(buf_t *b) {
  __asm volatile ("subq $8, %rsp\n call tail_elsewhere\n addq $8, %rsp\n addl $100, %eax\n ret\n");
}
int main(void) { buf_t b = {0, 0}; unsigned r = grab(&b); unsigned r2 = grab_call(&b);
  printf("r %u rip %d r2 %u\n", r, b.rip != 0, r2); return 0; }
