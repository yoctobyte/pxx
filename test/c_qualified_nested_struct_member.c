/* A qualified nested aggregate member (`const struct X <body> *func;`) is a
   member, as nouveau nvif/parent.h needs.
   bug-c-a-qualified-nested-struct-member-is-dropped. Expected output is gcc's. */
#include <stdio.h>
struct obj;
struct parent {
	const struct parent_func {
		void (*debugf)(struct obj *, const char *fmt, ...) __attribute__((format(printf, 2, 3)));
		void (*errorf)(struct obj *, const char *fmt, ...) __attribute__((format(printf, 2, 3)));
	} *func;
};
static void dbg(struct obj *o, const char *f, ...) { printf("dbg %s\n", f); }
static const struct parent_func pf = { dbg, dbg };
int main(void) { struct parent p; p.func = &pf; p.func->errorf(0, "hello"); printf("%zu\n", sizeof(struct parent_func)); return 0; }
