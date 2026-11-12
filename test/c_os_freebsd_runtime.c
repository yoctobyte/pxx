/* C runtime (pxxcio) under --os=freebsd: environment, heap, file round trip,
   argv and main's return value as the exit status. Run by `make test-freebsd`
   on both kernels; output and exit status must match.
   feature-port-freebsd-native */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
int main(int argc, char **argv) {
  char *probe = getenv("PXX_TEST_PROBE");
  char *buf = malloc(64);
  strcpy(buf, "heap");
  printf("probe=%s argc=%d [%s] %s\n", probe ? probe : "(unset)", argc,
         argc > 1 ? argv[1] : "", buf);
  FILE *f = fopen("pxx_os_freebsd_c.txt", "w");
  fprintf(f, "x=%d\n", 42);
  fclose(f);
  f = fopen("pxx_os_freebsd_c.txt", "r");
  int x = 0;
  fscanf(f, "x=%d", &x);
  fclose(f);
  remove("pxx_os_freebsd_c.txt");
  printf("read back %d\n", x);
  free(buf);
  return 3;
}
