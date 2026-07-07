/* Regression: a C function returning a pointer that returns a string literal
   must yield the char data (Offset+8), not the frozen length prefix. Was zlib's
   `zlibVersion(){ return ZLIB_VERSION; }` -> ver()[0]==5 not '1'. */
const char *ver(void){ return "1.3.1"; }
static const char *pick(int k){ return k ? "yes" : "no"; }
int main(void){
  const char *v = ver();
  if (v[0] != '1' || v[1] != '.' || v[4] != '1') return 1;
  if (pick(1)[0] != 'y') return 2;
  if (pick(0)[0] != 'n') return 3;
  return 42;
}
