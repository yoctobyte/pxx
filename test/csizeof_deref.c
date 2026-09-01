/* sizeof through MORE THAN ONE dereference.
 *
 * `sizeof(**p)' answered the POINTER size. The operand path consumed exactly
 * one `*' and then required an identifier, so a second star matched no branch
 * and the size kept its pointer-size default. gcc 16, pxx 8.
 *
 * WHERE IT LANDS IS AN ALLOCATION, which is what makes it expensive rather than
 * merely wrong: busybox ash's `stzalloc(sizeof(**nlpp))' reserved 8 bytes for a
 * 16-byte struct, so writing the parsed node through it ran off the end of the
 * block and the next allocation's header overwrote the previous node. The
 * visible symptom was a command substitution running a command whose NAME was
 * garbage -- three layers from sizeof, with no diagnostic anywhere.
 * Found attempting rung 2 (feature-c-corpus-busybox-multi-applet).
 *
 * The FEWER-STARS-THAN-DEPTH rows are here on purpose: `sizeof(*p2)' on a
 * `T**' must stay 8. A "fix" that always returned the ultimate base size would
 * pass the ** rows and break these, and it is the same one-line edit.
 *
 * NOT COVERED, and filed as bug-c-sizeof-reaches-a-pointee-through-one-spelling
 * -only: the SUBSCRIPT and mixed spellings of the same idea -- p2[0][0],
 * p3[0][0][0], *p2[0], **&p2[0], *(*p2) -- all still answer 8 where gcc says
 * 40. They are a different arm of the same concept and want the expression-type
 * machinery rather than another token-pattern branch, so they are not bodged in
 * here. Asserting them would make this file red; naming them keeps the gap
 * visible instead of silent.
 */
#include <stdio.h>

struct nl { struct nl *next; int n; };      /* 16 bytes on LP64 */
struct big { char pad[40]; };

int main(void) {
  struct nl *p1 = 0; struct nl **p2 = 0; struct nl ***p3 = 0;
  struct big *b1 = 0; struct big **b2 = 0;

  /* full depth: the pointee's real size */
  printf("1 %d %d\n", (int)sizeof(*p1),  (int)sizeof(struct nl));
  printf("2 %d %d\n", (int)sizeof(**p2), (int)sizeof(struct nl));
  printf("3 %d %d\n", (int)sizeof(***p3),(int)sizeof(struct nl));
  printf("4 %d %d\n", (int)sizeof(*b1),  (int)sizeof(struct big));
  printf("5 %d %d\n", (int)sizeof(**b2), (int)sizeof(struct big));

  /* fewer stars than depth: still a pointer, must NOT be the base size */
  printf("6 %d %d\n", (int)sizeof(*p2),  (int)sizeof(struct nl *));
  printf("7 %d %d\n", (int)sizeof(**p3), (int)sizeof(struct nl *));
  printf("8 %d %d\n", (int)sizeof(p2),   (int)sizeof(struct nl **));
  return 0;
}
