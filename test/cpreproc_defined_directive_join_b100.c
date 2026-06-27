/* Preprocessor directives inside a continued C expression must stay directives.
   sqlite has:
     if( p == &posixIoMethods
     #if defined(__APPLE__) && SQLITE_ENABLE_LOCKING_STYLE
       || p == &nfsIoMethods
     #endif
     )
   The physical-line joiner used to paste #if/#endif into the C line. Also cover
   `X && defined(Y)` and `!defined(Y)` expression forms. Exit 42. */
#define X 1

int main(void) {
  int r = 0;
  if (1
#if X && defined(MISSING)
      || 0
#endif
  ) r += 20;
#if !defined(MISSING)
  r += 21;
#endif
#if X && defined(X)
  r += 1;
#endif
  return r;
}
