/* Block-scope record initializer with function-pointer fields.
   SQLite's sqlite3MemSetDefault uses this shape for sqlite3_mem_methods.
   Exit 42. */
struct methods {
  void *(*xMalloc)(int);
  int (*xRoundup)(int);
  void *pAppData;
};

static void *my_malloc(int n) {
  return (void *)(long)(n + 1);
}

static int my_roundup(int n) {
  return n + 2;
}

static int call_methods(void) {
  static const struct methods m = {
    my_malloc,
    my_roundup,
    0
  };
  if ((long)m.xMalloc(41) != 42) return 1;
  if (m.xRoundup(40) != 42) return 2;
  if (m.pAppData != 0) return 3;
  return 42;
}

int main(void) {
  return call_methods();
}
