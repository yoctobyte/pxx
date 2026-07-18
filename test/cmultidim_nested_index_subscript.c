/* Regression: a multi-dim array subscript that is itself a multi-dim array read
   (`g3[g9[i][j][k]][..]`) re-entered the flatten during parse and CLOBBERED the
   shared NDInfo* AND NDIdxNode[] globals with the inner array's data -> corrupted
   g3's row-major flatten (silent wrong element on read; wrong slot on write;
   IR_UNSUPPORTED on some lvalues). csmith seeds 5004/40020. Fixed by capturing
   the subscript nodes locally and re-filling both globals before the flatten.
   Exit 42. */
static int g3[3][3] = {{0,1,2},{3,4,5},{6,7,8}};      /* g3[i][j] == i*3+j */
static int g9[3][1][3] = {{{0,0,0}},{{0,0,0}},{{2,0,0}}};  /* g9[2][0][0]=2 */
int main(void){
  int r = g3[1][g9[2][0][0]];         /* g3[1][2] = 5 (read, inner nested) */
  g3[g9[0][0][0]][g9[2][0][0]] = 88;  /* g3[0][2] = 88 (both nested, lvalue) */
  if (r == 5 && g3[0][2] == 88 && g3[0][0] == 0 && g3[1][0] == 3 && g3[2][2] == 8)
    return 42;
  return 0;
}
