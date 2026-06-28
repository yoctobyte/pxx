#define SQLITE_THREADSAFE 0
#define SQLITE_OMIT_LOAD_EXTENSION 1

#include "ctype.c"
#include "string.c"
#include "stdlib.c"
#include "stdio.c"
#include "math.c"
#include "locale.c"
#include "sqlite3.c"

#define OFF(T, F) ((unsigned long)&(((T *)0)->F))

int main(void) {
  printf("sizeof Expr=%lu flags=%lu pLeft=%lu iTable=%lu\n",
         (unsigned long)sizeof(Expr),
         OFF(Expr, flags),
         OFF(Expr, pLeft),
         OFF(Expr, iTable));
  printf("sizeof ExprList_item=%lu pExpr=%lu zEName=%lu fg=%lu u=%lu\n",
         (unsigned long)sizeof(struct ExprList_item),
         OFF(struct ExprList_item, pExpr),
         OFF(struct ExprList_item, zEName),
         OFF(struct ExprList_item, fg),
         OFF(struct ExprList_item, u));
  printf("sizeof SrcItem=%lu pTab=%lu pSelect=%lu fg=%lu iCursor=%lu u3=%lu colUsed=%lu u1=%lu u2=%lu\n",
         (unsigned long)sizeof(SrcItem),
         OFF(SrcItem, pTab),
         OFF(SrcItem, pSelect),
         OFF(SrcItem, fg),
         OFF(SrcItem, iCursor),
         OFF(SrcItem, u3),
         OFF(SrcItem, colUsed),
         OFF(SrcItem, u1),
         OFF(SrcItem, u2));
  printf("sizeof SrcList=%lu nSrc=%lu a=%lu\n",
         (unsigned long)sizeof(SrcList),
         OFF(SrcList, nSrc),
         OFF(SrcList, a));
  printf("sizeof Column=%lu zCnName=%lu affinity=%lu szEst=%lu hName=%lu iDflt=%lu colFlags=%lu\n",
         (unsigned long)sizeof(Column),
         OFF(Column, zCnName),
         OFF(Column, affinity),
         OFF(Column, szEst),
         OFF(Column, hName),
         OFF(Column, iDflt),
         OFF(Column, colFlags));
  printf("sizeof Table=%lu aCol=%lu nCol=%lu zName=%lu\n",
         (unsigned long)sizeof(Table),
         OFF(Table, aCol),
         OFF(Table, nCol),
         OFF(Table, zName));
  printf("sizeof sqlite3_pcache_page=%lu pBuf=%lu pExtra=%lu\n",
         (unsigned long)sizeof(sqlite3_pcache_page),
         OFF(sqlite3_pcache_page, pBuf),
         OFF(sqlite3_pcache_page, pExtra));
  printf("sizeof PgHdr=%lu pPage=%lu pData=%lu pExtra=%lu pCache=%lu pDirty=%lu pPager=%lu pgno=%lu flags=%lu nRef=%lu pDirtyNext=%lu pDirtyPrev=%lu\n",
         (unsigned long)sizeof(PgHdr),
         OFF(PgHdr, pPage),
         OFF(PgHdr, pData),
         OFF(PgHdr, pExtra),
         OFF(PgHdr, pCache),
         OFF(PgHdr, pDirty),
         OFF(PgHdr, pPager),
         OFF(PgHdr, pgno),
         OFF(PgHdr, flags),
         OFF(PgHdr, nRef),
         OFF(PgHdr, pDirtyNext),
         OFF(PgHdr, pDirtyPrev));
  printf("sizeof PgHdr1=%lu page=%lu iKey=%lu isBulkLocal=%lu isAnchor=%lu pNext=%lu pCache=%lu pLruNext=%lu pLruPrev=%lu\n",
         (unsigned long)sizeof(PgHdr1),
         OFF(PgHdr1, page),
         OFF(PgHdr1, iKey),
         OFF(PgHdr1, isBulkLocal),
         OFF(PgHdr1, isAnchor),
         OFF(PgHdr1, pNext),
         OFF(PgHdr1, pCache),
         OFF(PgHdr1, pLruNext),
         OFF(PgHdr1, pLruPrev));
  return 0;
}
