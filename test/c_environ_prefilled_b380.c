/* environ must already hold the real environment when main starts.
   feature-c-entry-stub-must-run-initializers-for-environ

   It was a CLEAN compile producing NULL: `environ` is a variable read
   directly, so no call ever triggered crtl's lazy /proc/self/environ load and
   nothing warned. This is the init half of the entry stub; the fini half is
   test/cfinalizers_on_main_return_b379.c, and both now live in the same stub.

   Self-consistent on purpose -- it asserts nothing about WHICH variables the
   environment holds, only that what environ points at is a real one and that
   getenv() agrees with it. A test that wanted PATH would be testing the build
   machine. */
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

int main(void)
{
  char **e = environ;
  char name[256];
  const char *eq, *v;
  int n = 0;

  if (!e) return 1;                      /* the bug: NULL where gcc has the env */
  while (e[n]) {
    if (!strchr(e[n], '=')) return 2;    /* every entry is NAME=VALUE */
    n++;
  }
  if (n == 0) return 3;                  /* a process started by make has one */

  /* getenv() and environ must describe the same environment: take the first
     entry's own name back through getenv and require its own value. */
  eq = strchr(e[0], '=');
  if ((size_t)(eq - e[0]) >= sizeof(name)) return 42;  /* absurd name length: skip the cross-check rather than fail on it */
  memcpy(name, e[0], (size_t)(eq - e[0]));
  name[eq - e[0]] = '\0';
  v = getenv(name);
  if (!v) return 4;
  if (strcmp(v, eq + 1) != 0) return 5;

  return 42;
}
