/* Four-argument function-pointer calls must preserve 64-bit pointer args past
   the first slot. Lua calls g->frealloc(ud, block, os, ns). Exit 42. */
struct Box { long v; };
typedef long (*AllocFn)(void *, void *, unsigned long, unsigned long);
struct Holder { AllocFn f; };

static struct Box a;

static long check(void *ud, void *ptr, unsigned long oldsz, unsigned long newsz) {
  struct Box *b = (struct Box *)ptr;
  return (ud == 0 ? 1 : 100) + b->v + (long)oldsz + (long)newsz;
}

int main(void) {
  AllocFn fp;
  struct Holder h;
  a.v = 9;
  fp = check;
  h.f = check;
  return (int)(fp(0, &a, 11, 21) + h.f(0, &a, 1, 1) - 12);
  /* 42 + (1 + 9 + 1 + 1) - 12 = 42 */
}
