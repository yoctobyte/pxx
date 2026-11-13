/* Extern objects declared while their struct type is still INCOMPLETE, the
 * way dropbear's algo.h declares dropbear_nocipher, dropbear_mode_none and
 * dropbear_nohash ahead of their struct definitions.
 *
 * Each sized to 0 at declaration, so all of them sat at one .bss offset. The
 * object writer names an import by its offset, so `&nohash` was relocated to
 * `nocipher`, the first name at that offset: a pointer to the wrong object,
 * with no diagnostic. The shared offset also made every one of them count as
 * "referenced", so `client_only`, which this TU never uses and the other TU
 * never defines, became an undefined symbol and the link failed.
 *
 * Built as two objects with --emit-obj and linked with --link (the shape that
 * failed); the definitions live in c_incomplete_extern_distinct_b.c.
 * Expected output is gcc's.
 */
#include <stdio.h>

extern const struct cipher nocipher;
extern const struct mode mode_none;
extern const struct hash nohash;
extern const struct chantype client_only;   /* declared, never used, never defined */

struct cipher { const char *name; int keylen; };
struct mode { const char *name; };
struct hash { const char *name; int len; };
struct chantype { int x; };

int main(void)
{
  const struct hash *h = &nohash;
  const struct mode *m = &mode_none;
  const struct cipher *c = &nocipher;
  printf("%s %d\n", c->name, c->keylen);
  printf("%s\n", m->name);
  printf("%s %d\n", h->name, h->len);
  printf("distinct %d %d\n", (const void *)h != (const void *)c, (const void *)m != (const void *)c);
  return 0;
}
