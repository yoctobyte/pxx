/* the other translation unit for test/c_alias_attribute.c */
#include <stdio.h>
int vsum(int n, ...); int add(int, int); int weakname(void); extern int counter, counter_storage;
int main(void) { counter++; printf("add %d vsum %d weak %d counter %d/%d\n", add(2, 3), vsum(3, 1, 2, 3), weakname() + 1, counter, counter_storage); return 0; }
