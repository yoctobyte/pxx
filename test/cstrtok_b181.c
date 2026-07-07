/* Regression: crtl strtok / strtok_r (were missing from lib/crtl). */
#include <string.h>
int main(void){
  char a[] = "hello,world,,foo";   /* empty field between commas skipped */
  int n = 0; char *t;
  for (t = strtok(a, ","); t; t = strtok(0, ",")) n++;
  if (n != 3) return 1;
  char b[] = ":a::b:";             /* leading/trailing/adjacent delims */
  char *sv; int m = 0;
  for (t = strtok_r(b, ":", &sv); t; t = strtok_r(0, ":", &sv)) m++;
  if (m != 2) return 2;            /* "a","b" */
  char c[] = "one two three";
  n = 0;
  for (t = strtok(c, " "); t; t = strtok(0, " ")) n++;
  if (n != 3) return 3;
  if (strcmp(a, "hello") != 0) return 4;   /* first token NUL-terminated in place */
  return 42;
}
