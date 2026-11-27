/* -std=c23 / gnu23: what pxx's C23 mode reads, compared with gcc's -std=c23
   output (wlroots compiles every unit as C23). feature-c-std-c23 */
#include <stdio.h>
#include <stdbool.h>
#include <stddef.h>
#include <assert.h>

#define KIND(x) _Generic((x), _Bool: "bool", int: "int", default: "other")

#if true && !false
static const char *pp_true = "#if true is 1";
#else
static const char *pp_true = "#if true is 0";
#endif

#ifdef bool
static const char *pp_bool = "bool is a macro";
#else
static const char *pp_bool = "bool is not a macro";
#endif

#ifdef true
static const char *pp_truem = "true is a macro";
#else
static const char *pp_truem = "true is not a macro";
#endif

struct s {
  char c;
  alignas(16) int v;
  [[maybe_unused]] int spare;
};

static_assert(sizeof(bool) == 1);                 /* C23: no message needed */
static_assert(alignof(struct s) == 16, "alignof");

[[nodiscard]] static int twice(int x) { return 2 * x; }
[[deprecated("use twice(]] instead")]] static int old_twice(int x) { return x + x; }
[[gnu::always_inline, gnu::unused]] static inline int three(void) { return 3; }
static thread_local int tl = 7;

static int sw(int k) {
  int r = 0;
  switch (k) {
  case 0:
    r += 1;
    [[fallthrough]];
  case 1:
    r += 10;
    break;
  default:
    r = -1;
  }
  return r;
}

int main(void) {
  bool b = 256;            /* converts to 1 */
  [[maybe_unused]] int unused_local = 0;
  typeof(b) b2 = false;
  printf("%s / %s / %s\n", pp_true, pp_bool, pp_truem);
  printf("stdc %ld\n", (long)__STDC_VERSION__);
  printf("sizeof true %d bool %d, kind true %s 1 %s b %s\n", (int)sizeof(true), (int)sizeof(bool),
         KIND(true), KIND(1), KIND(b));
  printf("b %d b2 %d !b %d true+true %d\n", b, b2, !b, true + true);
  printf("alignof s %d offsetof v %d\n", (int)alignof(struct s), (int)offsetof(struct s, v));
  printf("twice %d old %d three %d tl %d sw %d %d %d\n", twice(4), old_twice(5), three(), tl, sw(0), sw(1), sw(9));
  /* __has_c_attribute is an #if operator (C23 6.10.1) */
#if __has_c_attribute(nodiscard) == 202311L && __has_c_attribute(fallthrough) == 202311L && \
    __has_c_attribute(deprecated) == 202311L && __has_c_attribute(noreturn) == 202311L && \
    __has_c_attribute(maybe_unused) == 202311L && __has_c_attribute(unsequenced) == 202311L
  printf("has_c_attribute standard: 202311\n");
#endif
#if __has_c_attribute(gnu::always_inline) && __has_c_attribute(__gnu__::__unused__)
  printf("has_c_attribute gnu: yes\n");
#endif
#if !__has_c_attribute(no_such_attribute)
  printf("has_c_attribute unknown: 0\n");
#endif
#ifdef __has_c_attribute
  printf("has_c_attribute is defined\n");
#endif
  printf("__bool_true_false_are_defined %d\n", __bool_true_false_are_defined);
  return 0;
}
