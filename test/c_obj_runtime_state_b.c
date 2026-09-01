/* Half B -- see c_obj_runtime_state_a.c. */
#include <stdio.h>
#include <stdlib.h>
#include <errno.h>
#include <unistd.h>

void *ra_alloc(void);
void ra_fail_open(void);
void ra_scan(int argc, char **argv);

int main(void)
{
  char *av[4];
  char *p;

  av[0] = "prog"; av[1] = "-u"; av[2] = "file"; av[3] = 0;

  p = (char *)ra_alloc();
  printf("%s ", p);
  free(p);

  errno = 0;
  ra_fail_open();
  printf("errno=%d ", errno);

  ra_scan(3, av);
  printf("optind=%d\n", optind);
  return 0;
}
