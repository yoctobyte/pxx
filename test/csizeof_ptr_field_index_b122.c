/* sizeof(pointer_field[index]) must return the pointed element size, not the
   pointer size. SQLite uses sizeof(p->aCol[0]) when growing Column arrays.
   Exit 42. */
struct Column {
  char *zCnName;
  unsigned notNull : 4;
  unsigned eCType : 4;
  char affinity;
  unsigned char szEst;
  unsigned char hName;
  unsigned short iDflt;
  unsigned short colFlags;
};

struct Table {
  struct Column *aCol;
};

int main(void) {
  struct Table tab;
  struct Table *p = &tab;
  if (sizeof(struct Column) != 16) return 1;
  if (sizeof(p->aCol[0]) != 16) return 2;
  return sizeof(p->aCol[0]) + 26;
}
