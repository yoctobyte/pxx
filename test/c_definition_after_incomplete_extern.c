/* A definition that follows an `extern` declaration made while its struct
 * type was still incomplete, dropbear's common-algo.c shape:
 *
 *   algo.h:        extern const struct dropbear_cipher dropbear_nocipher;
 *   (later)        struct dropbear_cipher { ... };
 *   common-algo.c: const struct dropbear_cipher dropbear_nocipher = {NULL, 16, 8};
 *
 * The declaration reserved a slot of the incomplete size and the definition
 * reused the row without resizing it. A const definition lost its initialiser
 * entirely (dropbear read blocksize 0 and its first packet died with
 * "division by zero"); a non-const one wrote 16 bytes into a 1-byte slot and
 * read back right only because nothing else used the bytes it overran. The
 * guards around the definitions catch an overrun; `early` takes the address
 * before the definition is seen. Expected output is gcc's.
 */
#include <stdio.h>

extern const struct cipher nocipher;
extern const struct hash nohash;
extern struct cipher mut;

static const struct cipher *early(void) { return &nocipher; }

struct cipher { const char *name; int keylen; int blocksize; };
struct hash { const char *name; long len; char pad[40]; };

static int early_mut(void) { mut.keylen += 5; return mut.blocksize; }

int guard_before = 0x11111111;
const struct cipher nocipher = { "none", 16, 8 };
struct cipher mut = { "mut", 1, 2 };
const struct hash nohash = { "nohash", 20, "x" };
int guard_after = 0x22222222;

int main(void)
{
  const struct cipher *c = early();
  int b = early_mut();
  printf("%s %d %d\n", c->name, c->keylen, c->blocksize);
  printf("%s %d %d %d\n", mut.name, mut.keylen, mut.blocksize, b);
  printf("%s %ld %s\n", nohash.name, nohash.len, nohash.pad);
  printf("%x %x\n", guard_before, guard_after);
  printf("distinct %d sizes %d %d\n", (const void *)&nocipher != (const void *)&nohash,
         (int)sizeof nocipher, (int)sizeof nohash);
  return 0;
}
