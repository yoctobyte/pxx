/* sizeof on a fixed array field reached through a struct pointer must return
   the whole array byte size, not the pointer size. SQLite uses
   memcpy(db->aLimit, aHardLimit, sizeof(db->aLimit)); if sizeof is 8 instead
   of 48, SQLITE_LIMIT_COLUMN remains zero and schema parsing reports corrupt.
   Exit 42. */
struct DB {
  int aLimit[12];
};

static const int hard[12] = { 1, 2, 2000, 4, 5, 6, 7, 8, 9, 10, 11, 12 };

static void copy_bytes(void *dest, const void *src, unsigned long n) {
  unsigned char *d = dest;
  const unsigned char *s = src;
  while (n > 0) {
    *d++ = *s++;
    n--;
  }
}

int main(void) {
  struct DB db;
  struct DB *p = &db;
  int i;
  for (i = 0; i < 12; i++) db.aLimit[i] = 0;
  if (sizeof(p->aLimit) != 48) return 1;
  copy_bytes(p->aLimit, hard, sizeof(p->aLimit));
  return p->aLimit[2] == 2000 && p->aLimit[11] == 12 ? 42 : 2;
}
