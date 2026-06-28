/* C ternary string-literal arms lower to a char* temp in C mode. Passing that
   ternary to a const char* parameter must not apply the frozen-string +8
   adapter a second time. SQLite's SCHEMA_TABLE(iDb) macro has this shape:
   cond ? "sqlite_temp_master" : "sqlite_master". Exit 42. */
static int len(const char *s) {
  int n = 0;
  while (s[n]) n++;
  return n;
}

static int starts_sqlite(const char *s) {
  return s[0] == 's' && s[1] == 'q' && s[2] == 'l' && s[7] == 'm';
}

int main(void) {
  const char *p = 0 ? "sqlite_temp_master" : "sqlite_master";
  int direct = len(0 ? "sqlite_temp_master" : "sqlite_master");
  if (!starts_sqlite(p)) return 1;
  if (!starts_sqlite(0 ? "sqlite_temp_master" : "sqlite_master")) return 2;
  return direct + len(p) + 16;  /* 13 + 13 + 16 = 42 */
}
