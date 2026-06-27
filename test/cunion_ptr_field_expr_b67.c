typedef struct GCObject {
  int tt;
  char contents[4];
} GCObject;

typedef union Value {
  GCObject *gc;
  void *p;
  long i;
  double n;
  unsigned char ub;
} Value;

typedef struct TValue {
  Value value_;
  unsigned char tt_;
} TValue;

typedef union StackValue {
  TValue val;
} StackValue;

typedef StackValue *StkId;

typedef union {
  StkId p;
  long offset;
} StkIdRel;

typedef struct lua_State {
  StkIdRel top;
} lua_State;

#define s2v(o) (&(o)->val)
#define val_(o) ((o)->value_)
#define gcvalue(o) (val_(o).gc)
#define getstr(ts) ((ts)->contents)

const char *top_string(lua_State *L) {
  return getstr(gcvalue(s2v(L->top.p - 1)));
}

int main(void) {
  StackValue stack[2];
  GCObject obj;
  lua_State L;
  const char *s;

  obj.contents[0] = 39;
  obj.contents[1] = 0;
  stack[0].val.value_.gc = &obj;
  L.top.p = stack + 1;

  s = top_string(&L);
  return *s + 3;
}
