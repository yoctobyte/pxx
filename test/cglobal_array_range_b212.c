/* Regression: GNU range designators [lo ... hi] = v in a GLOBAL scalar-array
   initializer. The global flat-int init path (ParseCGlobalVarDecl + the
   CBraceFlatIntInitCountAt scanner) parsed `[k]=` only and silently zero-filled
   on a range. Now fills lo..hi and sizes an unsized array to hi+1. gcc-verified.
   feature-c-compound-literals (00216 init battery). */
int t[8]  = { [0 ... 2] = 5, [5] = 9, [6 ... 7] = 1 };
int u[]   = { [0 ... 3] = 4 };                       /* unsized -> length 4 */
int main(void) {
  int i, s = 0, ok = 1;
  for (i = 0; i < 8; i++) s += t[i];
  if (s != 5*3 + 9 + 1*2) ok = 0;                    /* 15+9+2 = 26 */
  if (sizeof(u)/sizeof(u[0]) != 4) ok = 0;
  if (!(u[0]==4 && u[3]==4)) ok = 0;
  return ok ? 42 : 1;
}
