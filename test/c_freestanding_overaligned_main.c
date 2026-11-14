/* gcc-built driver for c_freestanding_overaligned.c */
#include <stdio.h>
unsigned long fs_mods(void);
int main(void) { printf("mods %lu\n", fs_mods()); return 0; }
