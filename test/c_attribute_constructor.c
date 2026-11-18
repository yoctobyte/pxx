/* __attribute__((constructor)) / ((destructor)): order, the attribute on a
   prototype only, both spellings, destructors at exit in reverse.
   Linked whole by pxx, and as a pxx --emit-obj object under a gcc main
   (c_attribute_constructor_main.c, -DCT_NO_MAIN).
   bug-c-constructor-and-destructor-attributes-were-dropped */
/* constructor/destructor attributes: order, prototype-only attribute,
   both spellings, and a destructor that prints at exit */
#include <stdio.h>

static int trace[8];
static int n;
int gv = 7;

static void first(void) __attribute__((constructor));
static void first(void) { trace[n++] = 1 + gv; }

__attribute__((__constructor__)) static void second(void) { trace[n++] = 2; }

static void bye(void) __attribute__((destructor));
static void bye(void) { printf("dtor bye\n"); }

__attribute__((destructor)) static void bye2(void) { printf("dtor bye2\n"); }

int ctor_count(void) { return n; }
int ctor_at(int i) { return trace[i]; }

#ifndef CT_NO_MAIN
int main(void)
{
  int i;
  printf("ctors %d:", ctor_count());
  for (i = 0; i < ctor_count(); i++) printf(" %d", ctor_at(i));
  printf("\n");
  return 0;
}
#endif
