typedef unsigned char lu_byte;
typedef long long lua_Integer;
typedef double lua_Number;

#define LUA_TNUMBER 3
#define makevariant(t,v) ((t) | ((v) << 4))
#define LUA_VNUMINT makevariant(LUA_TNUMBER, 0)

typedef union Value {
  void *p;
  lua_Integer i;
  lua_Number n;
  lu_byte ub;
} Value;

typedef struct TValue {
  Value value_;
  lu_byte tt_;
} TValue;

#define val_(o) ((o)->value_)
#define settt_(o,t) ((o)->tt_ = (t))
#define setivalue(obj,x) { TValue *io=(obj); val_(io).i=(x); settt_(io, LUA_VNUMINT); }
#define ivalue(o) (val_(o).i)

static lua_Integer add2(lua_Integer a, lua_Integer b) {
  TValue v;
  setivalue(&v, a + b);
  return ivalue(&v);
}

int main(void) {
  if (sizeof(lua_Integer) != 8) return 1;
  if (sizeof(TValue) < 9) return 2;
  if (add2(2, 2) != 4) return 3;
  if (add2(10000000000LL, 7) != 10000000007LL) return 4;
  return 42;
}
