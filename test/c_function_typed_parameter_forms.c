/* A parameter declared with FUNCTION type is a pointer to a function (C
   6.7.6.3p8), in every spelling of the declarator. Two spellings were not
   declared at all, so the body's use of the name was an "undeclared
   identifier":
     void free_data(struct cx *)      -- returning void: read as the `(void)'
                                         of an empty parameter list
     int (name2id)(const char *, ...)  -- the name in parentheses
   util-linux writes both (lib/path.c ul_path_set_dialect, lib/strutils.c
   string_to_idarray). The plain `int f(int)' and the pointer spellings are
   here as the controls. */
#include <stdio.h>
#include <string.h>

struct cx { void (*fr)(struct cx *); int n; };

static void bump(struct cx *c) { c->n += 10; }
static int twice(int x) { return 2 * x; }
static int len2id(const char *s, size_t n) { return (int)n * 100 + s[0]; }

static int set_dialect(struct cx *c, void *data, void free_data(struct cx *))
{
  (void)data;
  c->fr = free_data;
  return free_data != 0;
}
static int apply_plain(int f(int), int v) { return f(v); }
static int apply_paren(int (g)(int), int v) { return g(v) + 1; }
static int to_ids(const char *list, int (name2id)(const char *, size_t))
{
  const char *comma = strchr(list, ',');
  if (!name2id) return -1;
  return name2id(list, comma ? (size_t)(comma - list) : strlen(list));
}
static void call_void_paren(struct cx *c, void (done)(struct cx *)) { done(c); }
static int apply_ptr(int (*p)(int), int v) { return p(v); }

/* a prototype and its definition, both in the function-typed form */
static int later(int h(int));
static int later(int h(int)) { int (*p)(int) = h; return p(5); }

int main(void)
{
  struct cx c = { 0, 1 };
  printf("set_dialect %d\n", set_dialect(&c, 0, bump));
  c.fr(&c);
  printf("after free_data %d\n", c.n);
  call_void_paren(&c, bump);
  printf("after (done) %d\n", c.n);
  printf("plain %d paren %d ptr %d later %d\n", apply_plain(twice, 3), apply_paren(twice, 4),
         apply_ptr(twice, 6), later(twice));
  printf("name2id %d null %d\n", to_ids("ab,cd", len2id), to_ids("x", 0));
  printf("sizeof %d\n", (int)(sizeof(int (*)(int)) == sizeof(void *)));
  return 0;
}
