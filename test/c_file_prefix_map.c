/* -ffile-prefix-map=OLD=NEW / -fmacro-prefix-map=OLD=NEW rewrite __FILE__,
   in the main file and in a header found through -I; the last matching map
   wins, as in gcc. Built from an absolute path so the map has a prefix to
   replace. feature-c-ffile-prefix-map */
#include <stdio.h>
#include "fpm.h"
int main(void)
{
  printf("%s\n%s\n", __FILE__, header_file());
  return 0;
}
