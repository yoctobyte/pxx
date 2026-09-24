/* `--threadsafe --emit-obj` / `--shared` refused EVERY C file, this one
   included: with no entry stub the first runtime stub landed at code offset 0,
   and every stub-address variable reads 0 as "never emitted".
   bug-c-sqlite-with-threadsafe-stops-at-a-stray-BEGIN_DECLS */
int f(int x) { return x + 1; }
