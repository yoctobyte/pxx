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

typedef union StackValue {
  TValue val;
  struct {
    Value value_;
    lu_byte tt_;
    unsigned short delta;
  } tbclist;
} StackValue;

typedef StackValue *StkId;

int main(void) {
  StackValue stack[2];
  StkId o = stack;

  stack[1].val.tt_ = 42;
  o++;

  return o->val.tt_;
}
