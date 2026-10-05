#include "c_import_extern_vars.h"
#include <stdio.h>
pair_t g_pair = {1, 2};
const pair_t g_cpair = {3, 4};
int g_int = 5;
void show(void);
int main(void) { show(); printf("%d\n", g_pair.b); return 0; }
