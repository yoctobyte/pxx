/* Scalar ordinal global initializers `T x = <int literal>;` materialised via
   PendingInit (run at the start of main) — previously read zero. Exit 42. */
int g_a = 20;
static const int g_b = 13;
unsigned char g_c = 9;
int main(void) {
  return g_a + g_b + g_c;   /* 20 + 13 + 9 = 42 */
}
