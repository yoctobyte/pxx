typedef unsigned char lu_byte;

#define LUA_TNIL 0
#define makevariant(t,v) ((t) | ((v) << 4))
#define LUA_VABSTKEY makevariant(LUA_TNIL, 2)

typedef union Value {
  void *gc;
  long i;
} Value;

typedef struct TValue {
  Value value_;
  lu_byte tt_;
} TValue;

static const TValue absentkey = {{0}, LUA_VABSTKEY};

int main(void) {
  if (absentkey.value_.gc != 0) return 1;
  if (absentkey.tt_ != 32) return 2;
  return absentkey.tt_ + 10;
}
