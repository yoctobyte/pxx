typedef unsigned char lu_byte;

typedef struct GCObject {
  struct GCObject *next;
  lu_byte tt;
  lu_byte marked;
} GCObject;

typedef union Value {
  GCObject *gc;
  void *p;
  long i;
} Value;

typedef struct TValue {
  Value value_;
  lu_byte tt_;
} TValue;

typedef union Node {
  struct NodeKey {
    Value key_val;
    lu_byte key_tt;
    int next;
  } u;
  TValue i_val;
} Node;

int main(void) {
  Node nodes[3];
  Node *n, *limit = nodes + 2;

  nodes[1].i_val.tt_ = 42;
  nodes[2].i_val.tt_ = 7;

  n = nodes;
  n++;
  if (n->i_val.tt_ != 42) return 1;

  limit--;
  if (limit->i_val.tt_ != 42) return 2;

  return 42;
}
