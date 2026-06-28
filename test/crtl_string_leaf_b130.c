#include "string.c"

int main(void) {
  char buf[32];
  char xform[8];
  char *p;
  strcpy(buf, "ab");
  strcat(buf, "cd");
  strncat(buf, "efgh", 2);
  if (strcmp(buf, "abcdef") != 0) return 1;
  if (strrchr(buf, 'c') != buf + 2) return 2;
  if (memchr(buf, 'e', 6) != buf + 4) return 3;
  if (strspn("abc123", "abc") != 3) return 4;
  if (strcspn("abc123", "0123456789") != 3) return 5;
  p = strpbrk("hello", "xyzol");
  if (p == 0 || *p != 'l') return 6;
  if (strstr("portable c", "table") == 0) return 7;
  if (strcoll("aa", "ab") >= 0) return 8;
  if (strxfrm(xform, "copy", sizeof(xform)) != 4) return 9;
  if (strcmp(xform, "copy") != 0) return 10;
  if (strerror(5) == 0) return 11;
  return 42;
}
