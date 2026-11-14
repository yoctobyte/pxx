#include <stdio.h>
static volatile int v;
int main(void){ v=1; __asm__ volatile("mfence" ::: "memory"); __asm__ volatile("lfence\n\tsfence"); v++; printf("fence %d\n", v); return 0; }
