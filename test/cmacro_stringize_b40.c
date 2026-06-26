/* `#` stringize operator: `#x` becomes a string literal of the raw arg (lua
   lundump `#define checksize(S,t) fchecksize(S,sizeof(t),#t)`). Exit 42. */
#define NM(t) #t
static int streq(const char *a, const char *b) {
  while (*a && *a == *b) { a++; b++; }
  return *a == *b;
}
static int slen(const char *s) { int n = 0; while (s[n]) n++; return n; }
int main(void) {
  int ok = streq(NM(Instruction), "Instruction");   /* stringized name */
  int n  = slen(NM(hello));                          /* 5 */
  return (ok && n == 5) ? 42 : 0;
}
