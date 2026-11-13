/* A `static` function in one module and a function with EXTERNAL linkage of
   the same name in another are two functions (C 6.2.2), and a call from a
   third module must reach the external one.

   Found in dropbear: crtl's crypt.c has a private `static void
   sha512_init(sha512_ctx *)`, and libtomcrypt's `int sha512_init(hash_state *)`
   is external. Any dropbear file that included <crypt.h> pulled crypt.c into
   its buffer, and its call to libtomcrypt's sha512_init was BOUND TO crtl's
   static: the hash state was written 8 bytes off, ed25519 signatures were
   wrong, and OpenSSH said "incorrect signature" for every login.

   Both declaration orders are rows: the public prototype first (dropbear's
   order), and with -DSTATIC_FIRST the static module first. The oracle is
   gcc building the modules as separate TUs:
     gcc -DSEPARATE_TU test/c_static_vs_external_same_name.c \
         test/fixtures/cstatic_ext_priv.c test/fixtures/cstatic_ext_pub.c
   prints "10 1005 1007 14 10".
*/
extern int printf(const char *, ...);

#if defined(STATIC_FIRST) && !defined(SEPARATE_TU)
#include "fixtures/cstatic_ext_priv.c"
#endif

int tag(int);
int priv_user(int);
int (*priv_addr(void))(int);

#if !defined(STATIC_FIRST) && !defined(SEPARATE_TU)
#include "fixtures/cstatic_ext_priv.c"
#endif

int main(void)
{
  int (*pub)(int) = tag;
  printf("%d %d %d %d %d\n", tag(5), priv_user(5), priv_addr()(7), pub(7),
         pub == priv_addr() ? -1 : tag(5));
  return 0;
}

#ifndef SEPARATE_TU
#include "fixtures/cstatic_ext_pub.c"
#endif
