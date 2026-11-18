#include <stdio.h>
struct pl { void *a, *b; };
struct pl ifnet_pslist = { (void *)1, 0 };
int ipsec_debug = 40;
static void q(int x) { (void)x; }
void (*altq_input)(int) = q;
int stub_get(void);
int main(void) { printf("%d\n", stub_get()); return 0; }
