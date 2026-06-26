/* Unary `~` (bitwise NOT) in C constant expressions must be bitwise Int64, not
   boolean. gcc: N0=-1, N5=-6, NM=255. Exit 6. */
enum { N0 = ~0, N5 = ~5, NM = ~0 & 255 };
int main(void) {
  int ok = (N0 == -1) + (N5 == -6) + (NM == 255);   /* 3 */
  return ok + (~0 == -1 ? 3 : 0);                    /* +3 = 6 */
}
