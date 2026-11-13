/* Module with a PRIVATE helper named like a public function elsewhere: the
   shape of crtl's crypt.c (`static void sha512_init(sha512_ctx *)`) against
   libtomcrypt's `int sha512_init(hash_state *)`. Input to
   test/c_static_vs_external_same_name.c; never compiled alone. */
static int tag(int x) { return x + 1000; }
int priv_user(int x) { return tag(x); }
int (*priv_addr(void))(int) { return tag; }
