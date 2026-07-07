/* Regression: sizeof(*s.field) / sizeof(*s->field) is the field's POINTEE size,
   not the pointer size. Was 8 (default) for any pointer field, so zlib's
   CLEAR_HASH `(hash_size-1)*sizeof(*s->head)` (head a `Pos*`=ush*) zmemzero'd ~4x
   too much and wiped the deflate flush marker (inflateSync failed). */
typedef unsigned short ush;
typedef ush Pos;
struct inner { int a, b; };
struct st { Pos *head; unsigned short *raw; int *ip; struct inner *rp; };
int main(void){
  struct st s;
  struct st *p = &s;
  if (sizeof(*s.head) != 2) return 1;
  if (sizeof(*s.raw)  != 2) return 2;
  if (sizeof(*s.ip)   != 4) return 3;
  if (sizeof(*s.rp)   != sizeof(struct inner)) return 4;
  if (sizeof(*p->head) != 2) return 5;   /* -> form */
  if (sizeof(*p->ip)   != 4) return 6;
  return 42;
}
