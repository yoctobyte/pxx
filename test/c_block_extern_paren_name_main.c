#include <stdio.h>
struct pi { int v; };
int plain_v = 20;
static struct pi x = {20}, y = {2};
static struct pi *const ex __attribute__((section("link_set_t"), used)) = &x;
static struct pi *const ey __attribute__((section("link_set_t"), used)) = &y;
int sum(void);
int main(void) { printf("%d\n", sum()); return 0; }
