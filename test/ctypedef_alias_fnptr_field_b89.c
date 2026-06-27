/* Typedef alias to a struct must preserve the record id. Lua's file handles use
   `typedef luaL_Stream LStream`; losing the record id made `p->closef` resolve as
   offset 0 (the FILE* slot), so the close callback jumped through garbage. */
typedef int (*CloseFn)(void *);

typedef struct StreamBase {
  void *f;
  CloseFn closef;
} StreamBase;

typedef StreamBase Stream;

int closer(void *p) { return p ? 42 : 1; }

int aux(Stream *s) {
  volatile CloseFn cf = s->closef;
  s->closef = 0;
  return (*cf)(s->f);
}

int main(void) {
  Stream s;
  s.f = &s;
  s.closef = &closer;
  return aux(&s);
}
