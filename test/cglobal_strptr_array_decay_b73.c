/* Global `const char *const[]` initializer where one element is the name of a
   static char array (decays to char*), mixed with string-literal elements.
   The array-decay element must not poison the whole initializer (regression:
   all elements came out NULL), and each pointer must resolve. Mirrors lua's
   `luaT_typenames_` table that holds `udatatypename` among string literals. */

static unsigned long slen(const char *s) { unsigned long n = 0; while (s && s[n]) n++; return n; }

static const char ud[] = "userdata";

const char *const names[4] = { "nil", ud, "table", 0 };

int main(void) {
  if (names[0] == 0) return 1;
  if (names[1] == 0) return 2;          /* the array-decay element */
  if (names[2] == 0) return 3;
  if (names[3] != 0) return 4;          /* explicit NULL stays null */
  if (names[0][0] != 'n') return 5;
  if (names[2][0] != 't') return 6;
  /* sum of lengths: "nil"(3) + "table"(5) = 8, then +34 magic */
  return (int)(slen(names[0]) + slen(names[2])) + 34;
}
