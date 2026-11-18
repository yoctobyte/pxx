/* __attribute__((section("link_set_x"))) on an x86-64 object: NetBSD link sets
   across objects, walked through the linker's __start_/__stop_. Built twice
   (-DLS_SECOND), linked under a gcc main (c_attribute_section_link_set_main.c),
   also mixed with a gcc object. feature-c-section-attribute-on-x86-64-objects */
struct item { const char *name; int val; };

#define __link_set_add(set, sym) \
  static void const * const __link_set_##set##_sym_##sym \
  __attribute__((__section__("link_set_" #set), __used__)) = (const void *)&sym

#ifndef LS_SECOND
static struct item alpha = { "alpha", 1 };
static struct item beta = { "beta", 2 };
char pad_after = 'x';   /* a global right after the entries */
__link_set_add(items, alpha);
static int unrelated = 77;
__link_set_add(items, beta);
int ls_a_unrelated(void) { return unrelated + pad_after; }
#else
static struct item gamma = { "gamma", 3 };
__link_set_add(items, gamma);

extern const struct item * const __start_link_set_items[];
extern const struct item * const __stop_link_set_items[];
int items_count(void) { return (int)(__stop_link_set_items - __start_link_set_items); }
int items_sum(void)
{
  const struct item * const *p;
  int s = 0;
  for (p = __start_link_set_items; p < __stop_link_set_items; p++) s += (*p)->val * 10 + (*p)->name[0] - 'a';
  return s;
}
#endif
