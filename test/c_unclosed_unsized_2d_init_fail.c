/* Same bug, counter arm: an unsized leading dimension sizes itself from
   CBraceTopLevelInitCountAt, which detected the unterminated run and encoded it
   as -1 -- the same value that means "nothing to count", so every caller read
   it as a length rather than as the error it was. */
int a[][2] = { {1,2}, {3,4
int main(void){ return 0; }
