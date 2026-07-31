/* bug-c-line-file-func-and-predefined-macros-missing: __LINE__/__FILE__/
   __func__ must carry real values (both used directly and passed as
   arguments), and the config predefines (__unix__, __SIZEOF_*, __CHAR_BIT__,
   __BYTE_ORDER__) must be present and correct for this target. */
extern int strcmp(const char *a, const char *b);

int check_args(const char *f, int l, const char *fn) {
  if (strcmp(f, __FILE__) != 0) return 0;
  if (l != 25) return 0;
  if (strcmp(fn, "main") != 0) return 0;
  return 1;
}

int main() {
  if (__LINE__ != 15) return 1;
  if (*__FILE__ == 0) return 2;
  if (strcmp(__func__, "main") != 0) return 3;
#ifndef __unix__
  return 4;
#endif
  if (__SIZEOF_POINTER__ != sizeof(void *)) return 5;
  if (__SIZEOF_LONG__ != sizeof(long)) return 6;
  if (__CHAR_BIT__ != 8) return 7;
  if (__BYTE_ORDER__ != __ORDER_LITTLE_ENDIAN__) return 8;
  if (!check_args(__FILE__, __LINE__, __func__)) return 9;
  return 42;
}
