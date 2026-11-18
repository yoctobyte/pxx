/* gcc side: a 32-bit absolute relocation (R_X86_64_32), which pxx --link
   refuses outside --freestanding. The refused link must leave no output.
   bug-a-link-leaves-a-truncated-executable-after-a-refused-relocation */
int gv = 5;
int get(void) { int *p; __asm__("movl $gv, %%eax" : "=a"(p)); return *p; }
