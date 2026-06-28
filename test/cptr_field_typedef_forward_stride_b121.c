/* A struct pointer field whose element type is a typedef-forwarded struct must
   keep the pointee record after the struct body is seen. Otherwise p->aCol[j]
   uses pointer-size stride and reads non-pointer bytes as zCnName. Exit 42. */
typedef struct Column Column;

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
  Column *aCol;
};

int main(void) {
  struct Column cols[2];
  struct Table tab;
  const char *z;

  cols[0].zCnName = "zero";
  cols[0].colFlags = 0x1110;
  cols[1].zCnName = "name";
  cols[1].colFlags = 0x2220;
  tab.aCol = cols;

  z = tab.aCol[1].zCnName;
  if (z[0] != 'n') return 1;
  if (z[3] != 'e') return 2;
  return 42;
}
