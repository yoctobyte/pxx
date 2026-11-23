/* --freestanding at -O3 builds: the -O3 xmm8..13 pool wrap around an
 * indirect call (pxx's own RTL has one) used to trip the freestanding
 * no-SSE refusal, so no -O3 kernel built at all. */
typedef void (*hook_t)(void);
static hook_t pending;
static int ticks;
static void tick(void) { ticks++; }
void drain(void) { if (pending) pending(); }
int kmain(void) { pending = tick; drain(); drain(); return ticks; }
