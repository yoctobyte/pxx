/* Regression: a PARTIAL multi-dim array index (fewer subscripts than the array
   rank) is valid C and decays to a pointer to the remaining sub-array —
   g[1][3] on int[2][9][7] is int(*)[7]. pxx used to reject it with "wrong number
   of array subscripts" (bug-c-partial-multidim-array-index). Assign through the
   sub-array pointer, read back via a full index. Exit 42. */
static int g[2][9][7];
int main(void) {
  int (*row)[7] = g[1][3];   /* 2 of 3 dims */
  row[0][2] = 42;
  row[0][6] = 7;
  if (g[1][3][2] == 42 && g[1][3][6] == 7 && g[1][3][0] == 0)
    return g[1][3][2];       /* 42 */
  return 0;
}
