/* Regression: sizeof of an array TYPE-NAME must include the extent(s).
   pxx used to return just the element size (bug-c-sizeof-array-type-ignores-
   extent): sizeof(int[10]) gave 4 not 40. Exit 42. */
int main(void){
  if (sizeof(int[10]) == 40 && sizeof(char[5]) == 5 &&
      sizeof(int[2][3]) == 24 && sizeof(double[4]) == 32 &&
      sizeof(int) == 4 && sizeof(char[7]) == 7)
    return 42;
  return 0;
}
