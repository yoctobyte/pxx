/* Indexing through a pointer-valued struct field must use the field VALUE as the
   base, not the address of the field slot. SQLite uses pTab->aCol[j].zCnName.
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
  int guard0;
  struct Column *aCol;
  int guard1;
};

static struct Column cols[2];
static struct Table tab;

int main(void) {
  struct Table *pTab = &tab;
  struct Column *pCol;
  const char *z;

  cols[0].zCnName = "zero";
  cols[0].colFlags = 0x1110;
  cols[1].zCnName = "name";
  cols[1].colFlags = 0x2220;
  tab.guard0 = 1234;
  tab.aCol = cols;
  tab.guard1 = 5678;

  pCol = &pTab->aCol[1];
  if (pCol != &cols[1]) return 1;
  z = pTab->aCol[1].zCnName;
  if (z[0] != 'n') return 2;
  if (z[3] != 'e') return 3;
  return 42;
}
