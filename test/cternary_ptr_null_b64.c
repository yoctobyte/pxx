typedef struct Obj {
  struct Obj *next;
  int v;
} Obj;

Obj **choose(Obj **p) {
  return (*p == (Obj *)0) ? 0 : p;
}

int main(void) {
  Obj *head = (Obj *)1;
  Obj **p = &head;
  Obj **q = choose(p);

  return q == p ? 42 : 1;
}
