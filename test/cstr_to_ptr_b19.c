/* A C string literal assigned to a char* must land on char 0, not the Pascal
   length prefix. Covers local var, struct field, reassignment, and the
   still-working direct call-arg path. Exit 42. */
int len(const char *s) { int n = 0; while (*s) { n++; s++; } return n; }
struct S { const char *m; };
int main(void) {
  const char *a = "hello";        /* 5 */
  struct S s; s.m = "worldwide";  /* 9 */
  a = "ab";                       /* reassign -> 2 */
  int direct = len("0123456789");  /* call-arg path -> 10 */
  return len(a) + len(s.m) + direct + a[0] - 'a' + 21;
  /* 2 + 9 + 10 + ('a'-'a'=0) + 21 = 42 */
}
