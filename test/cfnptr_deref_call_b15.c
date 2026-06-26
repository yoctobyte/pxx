/* Indirect call through a parenthesized dereferenced fn-pointer: `(*p->cb)(args)`
   (and `(*v)(args)`) — lua's allocator idiom `(*g->frealloc)(...)`. Exit 42. */
typedef int (*Alloc)(int n);
struct G { Alloc frealloc; };
int dbl(int n) { return n * 2; }
int via_field(struct G *g) { return (*g->frealloc)(21); }   /* 42 */
int via_var(Alloc a) { return (*a)(20); }                   /* 40 */
int main(void) {
  struct G g; g.frealloc = dbl;
  return (via_field(&g) == 42 && via_var(dbl) == 40) ? 42 : 0;
}
