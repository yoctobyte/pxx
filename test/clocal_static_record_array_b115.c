/* Block-scope static record arrays: infer initializer count, preserve static
   storage, materialize record fields, and make sizeof(array) total bytes.
   SQLite's sqlite3_os_init uses this shape for its VFS registry table.
   Exit 42. */
struct V {
  int n;
  struct V *next;
  const char *name;
};

static struct V *list = 0;

static int reg(struct V *p, int makeDefault) {
  if (makeDefault || list == 0) {
    p->next = list;
    list = p;
  } else {
    p->next = list->next;
    list->next = p;
  }
  return 0;
}

static int init(void) {
  unsigned int i;
  static struct V a[] = {
    { 3, 0, "first" },
    { 4, 0, "second" },
    { 5, 0, "third" }
  };
  if ((sizeof(a) / sizeof(a[0])) != 3) return 10;
  for (i = 0; i < sizeof(a) / sizeof(struct V); i++) reg(&a[i], i == 0);
  return 0;
}

int main(void) {
  init();
  if (list == 0) return 1;
  if (list->n != 3) return 10 + list->n;
  if (list->next == 0) return 20;
  if (list->next->n != 5) return 30 + list->next->n;
  return 42;
}
